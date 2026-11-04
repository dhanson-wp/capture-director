import AppKit
import ApplicationServices
import CaptureDirectorKit

/// The app being recorded: finding it, launching a fresh copy with the job's environment,
/// framing its window, and putting everything back afterwards.
final class TargetApp {
    let url: URL
    let bundleId: String
    let name: String
    /// The copy this take launched. Only this one is filmed, driven, and quit afterwards.
    private(set) var launched: NSRunningApplication?
    private var window: AXUIElement?
    /// The launched window's frame before it was resized: the frame the app saved last time.
    private var originalFrame: CGRect?
    private var relaunchAfter = false

    init(_ ref: RecordJob.AppRef) throws {
        if let id = ref.bundleId, !id.isEmpty {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                throw RecorderError("Can't find the app \(id).")
            }
            self.url = url
            bundleId = id
        } else {
            let path = ref.path ?? ""
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path), let id = Bundle(url: url)?.bundleIdentifier else {
                throw RecorderError("Can't find the app \(path).")
            }
            self.url = url
            bundleId = id
        }
        let display = FileManager.default.displayName(atPath: url.path)
        name = display.hasSuffix(".app") ? String(display.dropLast(4)) : display
    }

    var pid: pid_t { launched?.processIdentifier ?? 0 }

    /// Quits every running copy except the recorder itself, politely only (Ruling I): a copy
    /// still running after 5 s may hold unsaved work, so the take stops instead of force-quitting it.
    func quitRunningCopies() async throws {
        let selfPid = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
        let running = apps.map { RunningApp(pid: $0.processIdentifier, bundleId: $0.bundleIdentifier) }
        relaunchAfter = shouldRelaunchAfter(running: running, bundleId: bundleId, selfPid: selfPid)
        let pids = Set(instancesToQuit(running: running, bundleId: bundleId, selfPid: selfPid))
        let copies = apps.filter { pids.contains($0.processIdentifier) }
        for app in copies { app.terminate() }
        await Self.waitUntilGone(copies, seconds: 5)
        if copies.contains(where: { !$0.isTerminated }) {
            // Nothing was quit by force, so there's nothing to reopen.
            relaunchAfter = false
            throw RecorderError("Quit \(name) first, then record again.")
        }
    }

    /// Launches a new copy with the job's environment.
    func launch(env: [String: String]) async throws {
        let config = NSWorkspace.OpenConfiguration()
        config.environment = Self.environment(merging: env)
        config.createsNewApplicationInstance = true
        config.activates = true
        config.addsToRecentItems = false
        config.promptsUserIfNeeded = false
        do {
            launched = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        } catch {
            throw RecorderError("I couldn't open \(name): \(error.localizedDescription)")
        }
    }

    /// Waits up to 15 s for the launched copy's main window.
    func waitForWindow(checkCancel: () throws -> Void) async throws {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            try checkCancel()
            if launched?.isFinishedLaunching == true, let found = AX.mainWindow(of: pid) {
                window = found
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        throw RecorderError("\(name) didn't open a window within 15 seconds.")
    }

    /// Moves and sizes the window to the layout, in whole points, and brings it to the front.
    func place(_ layout: FrameLayout) async {
        guard let window else { return }
        originalFrame = AX.frame(window)
        let frame = CGRect(x: layout.windowOrigin.x.rounded(), y: layout.windowOrigin.y.rounded(),
                           width: layout.windowSize.width.rounded(), height: layout.windowSize.height.rounded())
        AX.setFrame(window, frame)
        launched?.activate()
        AX.raise(window, of: pid)
        let deadline = Date().addingTimeInterval(3)
        while !isFrontWithKeyWindow, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// The launched copy is the frontmost app and one of its windows has keyboard focus.
    var isFrontWithKeyWindow: Bool {
        guard let launched, !launched.isTerminated else { return false }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == launched.processIdentifier
            && AX.focusedWindow(of: launched.processIdentifier) != nil
    }

    /// Puts things back: the window's original frame (so the app saves that, not the take's
    /// frame), quits the copy this take launched, and reopens the app normally if it was running before.
    func restore() async {
        if let window, let originalFrame, launched?.isTerminated == false {
            AX.setFrame(window, originalFrame)
        }
        if let launched { await Self.quit([launched]) }
        launched = nil
        window = nil
        if relaunchAfter {
            relaunchAfter = false
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.addsToRecentItems = false
            // A new instance, or LaunchServices may just activate the recorder when the target is Capture Director.
            config.createsNewApplicationInstance = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
    }

    /// Ruling J: the recorder's own environment, minus LaunchServices' per-process keys,
    /// with the job's values on top. Correct whether LaunchServices adds or replaces.
    static func environment(merging job: [String: String]) -> [String: String] {
        ProcessInfo.processInfo.environment
            .filter { !$0.key.hasPrefix("__CF") && !$0.key.hasPrefix("XPC_") }
            .merging(job) { _, mine in mine }
    }

    /// Quits a copy this take launched: politely, then by force after 5 s.
    private static func quit(_ apps: [NSRunningApplication]) async {
        guard !apps.isEmpty else { return }
        for app in apps { app.terminate() }
        await waitUntilGone(apps, seconds: 5)
        for app in apps where !app.isTerminated { app.forceTerminate() }
        await waitUntilGone(apps, seconds: 2)
    }

    private static func waitUntilGone(_ apps: [NSRunningApplication], seconds: Double) async {
        let deadline = Date().addingTimeInterval(seconds)
        while apps.contains(where: { !$0.isTerminated }), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
