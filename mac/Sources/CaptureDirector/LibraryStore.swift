import CaptureDirectorKit
import Foundation
import Observation

/// The library as the windows see it. Reads `library.json` and reloads when it
/// changes; every change goes through the CLI, never a direct write.
@MainActor
@Observable
final class LibraryStore {
    var library = Library()
    /// Why library.json couldn't be read, without a prefix. With no good
    /// library yet it fills the window; otherwise it's a banner over the
    /// last good copy. Cleared by the next good read.
    var readError: String?
    /// A change the CLI refused or couldn't make. A banner people dismiss;
    /// reloads leave it alone.
    var problem: String?
    /// Captures whose video file isn't at its path. Recomputed on every reload and once a
    /// second, since moving a file in Finder doesn't touch library.json.
    private(set) var missing: Set<String> = []
    /// True once a read succeeded, so a later bad read keeps showing the last good library.
    private(set) var hasLoaded = false

    @ObservationIgnored private let file: URL
    @ObservationIgnored private let cli: CLI?
    @ObservationIgnored private var watcher: LibraryWatcher?
    @ObservationIgnored private let writes = SerialRunner()
    @ObservationIgnored private var poll: Task<Void, Never>?
    @ObservationIgnored private var checking: Task<Void, Never>?
    @ObservationIgnored private var recheck = false

    /// The folder library.json lives in.
    var home: URL { file.deletingLastPathComponent() }

    /// The CLI is set up, so changes can be written.
    var canWrite: Bool { cli != nil }

    init(file: URL, cli: CLI?) {
        self.file = file
        self.cli = cli
    }

    /// Loads once, then reloads whenever the file's folder changes.
    func start() {
        reload()
        guard watcher == nil else { return }
        let w = LibraryWatcher(file: file) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        w.start()
        watcher = w
        // Weak, so the loop ends when the store goes away; stop() ends it sooner.
        poll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                // A check that's still waiting on a slow drive isn't stacked on.
                if self.checking == nil { await self.refreshMissing() }
            }
        }
    }

    /// Stops watching and polling.
    func stop() {
        poll?.cancel()
        poll = nil
        checking?.cancel()
        watcher = nil
    }

    /// Checks every capture's file again, off the main actor: a video on a sleeping
    /// drive or a stalled share can take seconds to stat. Only a change publishes, so a
    /// quiet second redraws nothing. A call while a check runs waits for it, and the
    /// check then runs once more, so a change just made is never missed.
    func refreshMissing() async {
        if let running = checking {
            recheck = true
            await running.value
            return
        }
        let task = Task { @MainActor [weak self] in
            while let self {
                self.recheck = false
                let entries = self.library.entries
                let found = await Task.detached(priority: .utility) {
                    Browse.missing(entries) { FileManager.default.fileExists(atPath: $0) }
                }.value
                if Task.isCancelled { break }
                if found != self.missing { self.missing = found }
                if !self.recheck { break }
            }
            self?.checking = nil
        }
        checking = task
        await task.value
    }

    /// Keeps the last good library if the file can't be read.
    func reload() {
        do {
            library = try LibraryReader.load(from: file)
            Task { await refreshMissing() }
            hasLoaded = true
            readError = nil
        } catch {
            readError = error.localizedDescription
        }
    }

    /// "" is Unsorted. Values always go as one `--flag=value` argument, so text that
    /// starts with `--` or holds `=` arrives whole, and `--project=` is the top level.
    func setProject(_ ids: [String], _ path: String) async {
        guard !ids.isEmpty else { return }
        await write(["library", "set"] + ids + ["--project=\(FolderPath.normalize(path))"])
    }

    func setStarred(_ ids: [String], _ on: Bool) async {
        guard !ids.isEmpty else { return }
        await write(["library", "set"] + ids + [on ? "--star" : "--unstar"])
    }

    func setTitle(_ id: String, _ title: String) async {
        await write(["library", "set", id, "--title=\(title)"])
    }

    func setNotes(_ id: String, _ notes: String) async {
        await write(["library", "set", id, "--notes=\(notes)"])
    }

    func forget(_ ids: [String]) async {
        guard !ids.isEmpty else { return }
        if await write(["library", "forget"] + ids) { dropExports(ids) }
    }

    func relocate(_ id: String, to url: URL) async {
        if await write(["library", "relocate", id, url.path]) { dropExports([id]) }
    }

    func addFolder(_ path: String) async {
        await write(["library", "folder", "add", "--", path])
    }

    func renameFolder(_ from: String, to: String) async {
        await write(["library", "folder", "rename", "--", from, to])
    }

    func removeFolder(_ path: String) async {
        await write(["library", "folder", "remove", "--", path])
    }

    /// Copies being made or finished, by "<id>-<preset>". The store holds them, not the inspector,
    /// so selecting another capture and coming back still shows the copy, finished or not.
    private(set) var exports: [String: ExportJob] = [:]
    @ObservationIgnored private var exportTasks: [String: Task<ExportResult?, Never>] = [:]

    /// The copy to show for a capture: one in progress, else the newest finished.
    func exportJob(for id: String) -> ExportJob? {
        ExportJob.shown(ExportCopy.presets.compactMap { exports["\(id)-\($0)"] })
    }

    /// Makes (or reuses) a smaller copy of a capture for upload pages with size limits.
    /// Nil on failure, with `problem` set. A second ask while one is running joins it. It
    /// doesn't touch library.json, so it skips the serial runner: a long encode must not hold
    /// up a star click behind it.
    func exportCopy(_ id: String, preset: String) async -> ExportResult? {
        let key = "\(id)-\(preset)"
        if let running = exportTasks[key] { return await running.value }
        guard let cli else {
            problem = CLIError.notInstalled.message
            return nil
        }
        exports[key] = ExportJob(preset: preset)
        let task = Task { () -> ExportResult? in
            var result: ExportResult?
            do {
                let out = try await cli.run(["library", "export", id, "--preset=\(preset)"], timeout: CLI.exportTimeout)
                result = ExportCopy.decode(out)
                if result == nil { self.problem = "Capture Director couldn't read the copy's details." }
            } catch let error as CLIError {
                self.problem = error.message
            } catch {
                self.problem = error.localizedDescription
            }
            self.exportTasks[key] = nil
            self.exports[key] = result.map { ExportJob(preset: preset, result: $0) }
            return result
        }
        exportTasks[key] = task
        return await task.value
    }

    /// A copy goes away with its capture (forget) or its file (relocate), once the CLI
    /// made that change; a failed write leaves the copy showing.
    private func dropExports(_ ids: [String]) {
        for id in ids { for p in ExportCopy.presets { exports["\(id)-\(p)"] = nil } }
    }

    func export(_ id: String, preset: String) async -> URL? {
        await exportCopy(id, preset: preset)?.url
    }

    /// Runs the CLI off the main actor, then reloads. A failure becomes `problem`.
    /// Writes run one at a time in the order they were asked for: the CLI
    /// rewrites library.json without a lock, so two at once could lose one.
    /// True when the CLI made the change.
    @discardableResult
    private func write(_ args: [String]) async -> Bool {
        guard let cli else {
            problem = CLIError.notInstalled.message
            return false
        }
        return await writes.run { [weak self] in
            do {
                _ = try await cli.run(args)
                self?.problem = nil
                self?.reload()
                await self?.refreshMissing()
                return true
            } catch let error as CLIError {
                self?.problem = error.message
            } catch {
                self?.problem = error.localizedDescription
            }
            return false
        }
    }
}
