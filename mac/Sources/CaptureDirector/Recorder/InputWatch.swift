import CaptureDirectorKit
import CoreGraphics
import Foundation

/// Watches the session's real mouse and key events during a take, so Escape or a hand on
/// the mouse stops it. An event tap sees the original CGEvent with the posting pid
/// (0 for hardware) and the recorder's marker; an NSEvent global monitor only sees a
/// rebuilt copy without either, whose location isn't in screen coordinates.
///
/// The tap runs on its own thread so a slow Accessibility call on the main thread
/// never holds up the Mac's input. It passes every event through unchanged.
nonisolated final class InputWatch: @unchecked Sendable {
    private let lock = NSLock()
    private let selfPid = Int64(ProcessInfo.processInfo.processIdentifier)
    private var tap: CFMachPort?
    private var loop: CFRunLoop?
    private var verdict: InputVerdict?
    private var firstEvent: String?
    private var firstEventTaken = false

    /// Starts watching. Returns false when macOS won't allow the tap.
    func start() -> Bool {
        let ready = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var started = false
        let thread = Thread { [self] in
            let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .keyDown]
            let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
            guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                              eventsOfInterest: mask, callback: Self.callback,
                                              userInfo: Unmanaged.passUnretained(self).toOpaque()),
                  let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
                ready.signal()
                return
            }
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self.lock.withLock {
                self.tap = tap
                self.loop = loop
            }
            started = true
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "capture-director.input-watch"
        thread.start()
        ready.wait()
        return started
    }

    func stop() {
        let (tap, loop) = lock.withLock { (self.tap, self.loop) }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let loop { CFRunLoopStop(loop) }
        lock.withLock {
            self.tap = nil
            self.loop = nil
        }
    }

    /// Why the take should stop, if something other than the recorder moved the mouse or pressed Escape.
    var cancelReason: String? {
        switch lock.withLock({ verdict }) {
        case .escape: return "You pressed Escape, so the take stopped."
        case .userMoved: return "You moved the mouse, so the take stopped."
        default: return nil
        }
    }

    /// A one-time description of the first event the tap saw, for recorder.log.
    func takeFirstEventNote() -> String? {
        lock.withLock {
            guard !firstEventTaken, let firstEvent else { return nil }
            firstEventTaken = true
            return firstEvent
        }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = lock.withLock({ self.tap }) { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let isKey = type == .keyDown
        let sourcePid = event.getIntegerValueField(.eventSourceUnixProcessID)
        let userData = event.getIntegerValueField(.eventSourceUserData)
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let judged = judgeInput(isKey: isKey, keyCode: keyCode, sourcePid: sourcePid, userData: userData,
                                selfPid: selfPid, marker: InputDriver.marker)
        lock.withLock {
            if firstEvent == nil {
                let p = event.location
                firstEvent = "first input event seen: \(isKey ? "key \(keyCode)" : "pointer") from pid \(sourcePid) (ours is \(selfPid)), "
                    + "marker \(userData) (ours is \(InputDriver.marker)), at \(Int(p.x.rounded())),\(Int(p.y.rounded())), judged \(judged)"
            }
            if verdict == nil, judged == .escape || judged == .userMoved { verdict = judged }
        }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, info in
        if let info { Unmanaged<InputWatch>.fromOpaque(info).takeUnretainedValue().handle(type, event) }
        return Unmanaged.passUnretained(event)
    }
}
