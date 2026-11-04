import CaptureDirectorKit
import CoreGraphics
import Foundation

/// Watches the session's real mouse and key events during a take, so Escape or a hand on
/// the mouse stops it. An event tap sees the original CGEvent with the posting pid
/// (0 for hardware) and the recorder's marker; an NSEvent global monitor only sees a
/// rebuilt copy without either, whose location isn't in screen coordinates.
///
/// The tap is listen-only: it can't hold up or change the Mac's input, even if it stalls
/// or Accessibility is revoked mid-take. It runs on its own thread all the same.
nonisolated final class InputWatch: @unchecked Sendable {
    private let lock = NSLock()
    private let selfPid = Int64(ProcessInfo.processInfo.processIdentifier)
    private var tap: CFMachPort?
    private var loop: CFRunLoop?
    private var verdict: InputVerdict?
    private var firstEvent: String?
    private var firstEventTaken = false
    private var cancelEvent: String?
    private var cancelEventTaken = false

    /// Starts watching. Returns false when macOS won't allow the tap.
    func start() -> Bool {
        let ready = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var started = false
        let thread = Thread { [self] in
            let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .keyDown]
            let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
            guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
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
        // Cleared first, so a late tapDisabled callback finds no tap to turn back on.
        let (tap, loop) = lock.withLock {
            defer { self.tap = nil; self.loop = nil }
            return (self.tap, self.loop)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let loop { CFRunLoopStop(loop) }
    }

    /// Why the take should stop, if something other than the recorder moved the mouse or pressed Escape.
    var cancelReason: String? {
        switch lock.withLock({ verdict }) {
        case .escape: return "You pressed Escape, so the take stopped."
        case .userMoved: return "You moved the mouse, so the take stopped."
        default: return nil
        }
    }

    /// Notes for recorder.log not yet handed out: the first event the tap saw, and the
    /// event that stopped the take. Each is returned once.
    func takeNotes() -> [String] {
        lock.withLock {
            var notes: [String] = []
            if !firstEventTaken, let firstEvent {
                firstEventTaken = true
                notes.append("first input event seen: " + firstEvent)
            }
            if !cancelEventTaken, let cancelEvent {
                cancelEventTaken = true
                notes.append("the take stopped on input event: " + cancelEvent)
            }
            return notes
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
        let p = event.location
        let note = "\(isKey ? "key \(keyCode)" : "pointer") from pid \(sourcePid) (ours is \(selfPid)), "
            + "marker \(userData) (ours is \(InputDriver.marker)), at \(Int(p.x.rounded())),\(Int(p.y.rounded())), judged \(judged)"
        lock.withLock {
            if firstEvent == nil { firstEvent = note }
            if verdict == nil, judged == .escape || judged == .userMoved {
                verdict = judged
                cancelEvent = note
            }
        }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, info in
        if let info { Unmanaged<InputWatch>.fromOpaque(info).takeUnretainedValue().handle(type, event) }
        return Unmanaged.passUnretained(event)
    }
}
