import AppKit
import CaptureDirectorKit
import CoreMedia
import IOKit.pwr_mgt

// CaptureDirector --record /abs/job.json
// Records one Mac app shot with no window or Dock icon of its own. Writes raw.mov,
// capture.json, recorder.log, and always result.json into the job's `out` folder.
// Node launches it through LaunchServices so macOS grants the permissions to Capture Director.

struct RecorderError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// The person at the Mac stopped the take.
private struct Cancelled: Error {
    let message: String
}

enum RecordMode {
    static var requested: Bool { CommandLine.arguments.contains("--record") }

    /// Runs the take and returns the exit code: 0 only when the take is ok.
    static func run() async -> Int32 {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--record"), flag + 1 < args.count else {
            FileHandle.standardError.write(Data("--record needs the path to a job file.\n".utf8))
            return 1
        }
        let jobURL = URL(fileURLWithPath: args[flag + 1])
        let job: RecordJob
        do {
            job = try RecordJob.load(from: jobURL)
        } catch {
            // There's no out folder to write to, so the result goes next to the job file.
            let message = describe(error)
            FileHandle.standardError.write(Data("[capture-director] \(message)\n".utf8))
            writeResult(status: "error", message: message, to: jobURL.deletingLastPathComponent())
            return 1
        }
        let take = Take(job: job)
        return await take.run() ? 0 : 1
    }

    static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    static func writeResult(status: String, message: String?, to folder: URL) {
        struct Result: Encodable { var status: String; var message: String? }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Result(status: status, message: message)) else { return }
        try? data.write(to: folder.appendingPathComponent("result.json"), options: .atomic)
    }
}

/// One recording: set the app up, count down, film the steps, put everything back.
private final class Take {
    private let job: RecordJob
    private let out: URL
    private let movie: URL
    private let logFile: FileHandle?
    private let input = InputDriver()
    private var capture: CaptureLog
    private var target: TargetApp?
    private var recorder: ScreenRecorder?
    private var monitor: Any?
    private var layout = FrameLayout(windowSize: .zero, windowOrigin: .zero, sourceRect: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    /// Host time of the first frame: zero for every time in capture.json.
    private var start: Double = 0
    /// Where the pointer is, in 1920x1080 frame space.
    private var cursor: CGPoint
    private var cancelReason: String?
    private var reportedFirstEvent = false
    private var signalSources: [DispatchSourceSignal] = []
    private var awake: IOPMAssertionID = 0

    private static let settleBeforeClick = 140
    private static let clickHold = 80
    private static let keyHold = 50
    private static let typeDelay = 70
    private static let tick = 1.0 / 120

    init(job: RecordJob) {
        self.job = job
        out = URL(fileURLWithPath: job.out)
        movie = out.appendingPathComponent("raw.mov")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for name in ["raw.mov", "capture.json", "result.json", "recorder.log"] {
            try? FileManager.default.removeItem(at: out.appendingPathComponent(name))
        }
        let logURL = out.appendingPathComponent("recorder.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        logFile = try? FileHandle(forWritingTo: logURL)
        // Ruling C: the same default start as web shots.
        let start = job.cursorStart ?? [1920 * 0.62, 1080 * 0.72]
        capture = CaptureLog(cursorStart: start)
        cursor = CGPoint(x: start[0], y: start[1])
    }

    /// Returns true when the take is ok.
    func run() async -> Bool {
        watchSignals()
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                    IOPMAssertionLevel(kIOPMAssertionLevelOn), "Recording" as CFString, &awake)
        let status: String
        var message: String?
        do {
            try await record()
            status = "ok"
        } catch let cancelled as Cancelled {
            status = "cancelled"
            message = cancelled.message
        } catch {
            status = "error"
            message = RecordMode.describe(error)
        }
        await cleanUp(ok: status == "ok")
        IOPMAssertionRelease(awake)
        log(message ?? "done")
        RecordMode.writeResult(status: status, message: message, to: out)
        try? logFile?.close()
        return status == "ok"
    }

    // MARK: The take

    private func record() async throws {
        for case .press(let key) in job.steps where KeyChord(key) == nil {
            throw RecorderError("\(job.id): I don't know the key \"\(key)\".")
        }
        if let missing = Permissions.check() { throw RecorderError(missing) }
        let target = try TargetApp(job.app)
        self.target = target

        log("opening \(target.name)")
        try await target.quitRunningCopies()
        try await target.launch(env: job.env)
        try await target.waitForWindow()
        layout = try CaptureDirectorKit.layout(requested: CGSize(width: job.window.width, height: job.window.height),
                                               visible: Self.mainVisibleFrame())
        await target.place(layout)
        try checkFocus()

        input.move(to: screen(cursor))
        startWatching()
        try await pause(job.settle)
        var left = job.countdown
        while left > 0 {
            let whole = left.rounded(.up)
            log("starting in \(Int(whole))")
            let slice = left - (whole - 1)
            try await pause(Int((slice * 1000).rounded()))
            left -= slice
        }

        let recorder = try ScreenRecorder(url: movie, fps: job.fps)
        self.recorder = recorder
        try await recorder.start(pid: target.pid, sourceRect: layout.sourceRect,
                                 background: Self.color(job.background), fps: job.fps)
        start = try await recorder.firstFrame()
        log("recording \(job.steps.count) steps")

        for step in job.steps {
            try await perform(step)
            try checkCancel()
            try checkFocus()
        }
        try await pause(job.tail)
        try await recorder.finish(at: now)

        // Ruling G: the movie's real length, so the zoom plan and the video agree.
        let duration = try await recorder.duration()
        let data = try capture.json(duration: duration, source: "raw.mov")
        try data.write(to: out.appendingPathComponent("capture.json"), options: .atomic)
        log("wrote raw.mov (\(String(format: "%.2f", duration))s)")
    }

    private func perform(_ step: Step) async throws {
        switch step {
        case .wait(let ms):
            try await pause(ms)
        case .click(let target, let zoom, let hold, let duration):
            let (point, focus) = try await locate(target)
            try await glide(to: point, ms: duration)
            try await pause(Self.settleBeforeClick)
            let t = now - start
            input.mouseDown(at: screen(point))
            try await pause(Self.clickHold)
            input.mouseUp(at: screen(point))
            capture.click(t: t, released: now - start, x: point.x, y: point.y, zoom: zoom, focus: focus)
            if let hold { try await pause(hold) }
        case .hover(let target, let zoom, let hold, let duration):
            let (point, focus) = try await locate(target)
            try await glide(to: point, ms: duration)
            capture.hover(t: now - start, x: point.x, y: point.y, zoom: zoom, focus: focus)
            if let hold { try await pause(hold) }
        case .move(.point(let x, let y), let duration):
            try await glide(to: CGPoint(x: x, y: y), ms: duration)
        case .move(.target(let target), let duration):
            try await glide(to: try await locate(target).point, ms: duration)
        case .press(let key):
            guard let chord = KeyChord(key) else { return }
            input.keyDown(chord)
            try await pause(Self.keyHold)
            input.keyUp(chord)
        case .type(let text):
            for character in text {
                input.type(character)
                try await pause(Self.typeDelay)
            }
        case .scroll(let by, let duration):
            try await scroll(by: by, ms: duration ?? 1200)
        }
    }

    /// Finds a target's center and its focus box in frame space, polling every 100 ms for up to 5 s.
    private func locate(_ wanted: Target) async throws -> (point: CGPoint, focus: CaptureLog.Box) {
        guard let target else { throw RecorderError("The app isn't open.") }
        let deadline = Date().addingTimeInterval(5)
        repeat {
            try checkCancel()
            if let node = firstMatch(wanted, in: AXNode(app: target.pid)), let frame = node.frame {
                let box = toFrame(frame, in: layout)
                return (CGPoint(x: box.midX, y: box.midY), CaptureLog.Box(x: box.midX, y: box.midY, w: box.width, h: box.height))
            }
            try? await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline
        throw RecorderError("\(job.id): nothing matches \(Self.describe(wanted)) in \(target.name).")
    }

    /// Moves the real pointer along the eased curve at 120 Hz and logs the same move for the drawn cursor.
    private func glide(to end: CGPoint, ms: Int?) async throws {
        let from = cursor
        let distance = hypot(end.x - from.x, end.y - from.y)
        guard distance >= 0.5 else { return }
        let seconds = Double(ms ?? Int(min(900, 380 + distance * 0.45))) / 1000
        let t0 = now
        while true {
            try checkCancel()
            let p = seconds > 0 ? min(1, (now - t0) / seconds) : 1
            let e = ease(p)
            input.move(to: screen(CGPoint(x: from.x + (end.x - from.x) * e, y: from.y + (end.y - from.y) * e)))
            if p >= 1 { break }
            try? await Task.sleep(for: .seconds(Self.tick))
        }
        cursor = end
        capture.move(t0: t0 - start, t1: t0 - start + seconds, from: (from.x, from.y), to: (end.x, end.y))
    }

    /// Scrolls by `by` frame pixels on the eased curve, wherever the pointer is.
    private func scroll(by: Double, ms: Int) async throws {
        let total = by * layout.sourceRect.width / 1920
        let seconds = Double(ms) / 1000
        var sent = 0.0
        let t0 = now
        while true {
            try checkCancel()
            let p = seconds > 0 ? min(1, (now - t0) / seconds) : 1
            let delta = (total * ease(p) - sent).rounded()
            if delta != 0 {
                input.scroll(down: Int32(delta))
                sent += delta
            }
            if p >= 1 { break }
            try? await Task.sleep(for: .seconds(Self.tick))
        }
    }

    // MARK: Watching for the person at the Mac

    /// Escape, or any pointer movement the recorder didn't make, stops the take.
    private func startWatching() {
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .keyDown]
        ) { [weak self] event in
            self?.noticed(event)
        }
    }

    private func noticed(_ event: NSEvent) {
        guard cancelReason == nil else { return }
        let cg = event.cgEvent
        if !reportedFirstEvent {
            reportedFirstEvent = true
            let marker = cg.map { String($0.getIntegerValueField(.eventSourceUserData)) } ?? "none"
            log("first input event seen: cgEvent \(cg == nil ? "nil" : "present"), marker \(marker) (ours is \(InputDriver.marker))")
        }
        let isKey = event.type == .keyDown
        if input.posted(cg, location: cg?.location ?? Self.topLeft(NSEvent.mouseLocation),
                        keyCode: isKey ? CGKeyCode(event.keyCode) : nil) { return }
        if isKey {
            if event.keyCode == 53 { cancelReason = "You pressed Escape, so the take stopped." }
        } else {
            cancelReason = "You moved the mouse, so the take stopped."
        }
    }

    /// SIGTERM or SIGINT cancels the take, so cleanup still runs and result.json is written.
    private func watchSignals() {
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    if self?.cancelReason == nil { self?.cancelReason = "The take was stopped." }
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func checkCancel() throws {
        if let cancelReason { throw Cancelled(message: cancelReason) }
    }

    private func checkFocus() throws {
        guard target?.isFrontWithKeyWindow == true else {
            throw RecorderError("Another window took focus during the take.")
        }
    }

    /// Waits, stopping early if the take is cancelled.
    private func pause(_ ms: Int) async throws {
        let end = now + Double(ms) / 1000
        while true {
            try checkCancel()
            let left = end - now
            if left <= 0 { return }
            try? await Task.sleep(for: .seconds(min(left, 0.02)))
        }
    }

    // MARK: Putting things back

    private func cleanUp(ok: Bool) async {
        input.releaseAll()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let recorder {
            await recorder.stop()
            if !ok { recorder.cancel() }
        }
        await target?.restore()
        if !ok {
            try? FileManager.default.removeItem(at: movie)
            try? FileManager.default.removeItem(at: out.appendingPathComponent("capture.json"))
        }
    }

    // MARK: Helpers

    private var now: Double { CMClock.hostTimeClock.time.seconds }

    /// A frame point in global screen points.
    private func screen(_ p: CGPoint) -> CGPoint {
        let k = layout.sourceRect.width / 1920
        return CGPoint(x: layout.sourceRect.minX + p.x * k, y: layout.sourceRect.minY + p.y * k)
    }

    private func log(_ text: String) {
        let line = Data("[capture-director] \(job.id): \(text)\n".utf8)
        logFile?.write(line)
        FileHandle.standardError.write(line)
    }

    /// A Cocoa screen point (bottom-left origin) in global points with a top-left origin.
    private static func topLeft(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - p.y)
    }

    /// The main display's area outside the menu bar and Dock, in global points with a top-left origin.
    private static func mainVisibleFrame() throws -> CGRect {
        guard let screen = NSScreen.screens.first else { throw FrameError.displayTooSmall }
        let visible = screen.visibleFrame
        return CGRect(x: visible.minX, y: screen.frame.maxY - visible.maxY, width: visible.width, height: visible.height)
    }

    /// The validated `#rrggbb` background.
    private static func color(_ hex: String) -> CGColor {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return CGColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
                       blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }

    private static func describe(_ target: Target) -> String {
        switch target {
        case .id(let id): return id
        case .roleLabel(let role?, let label): return "\(role) \"\(label)\""
        case .roleLabel(nil, let label): return "\"\(label)\""
        }
    }
}
