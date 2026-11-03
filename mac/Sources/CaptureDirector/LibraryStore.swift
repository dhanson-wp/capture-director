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
        poll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refreshMissing()
            }
        }
    }

    /// Checks every capture's file again. Only a change publishes, so a quiet second redraws nothing.
    func refreshMissing() {
        let now = Browse.missing(library.entries) { FileManager.default.fileExists(atPath: $0) }
        if now != missing { missing = now }
    }

    /// Keeps the last good library if the file can't be read.
    func reload() {
        do {
            library = try LibraryReader.load(from: file)
            refreshMissing()
            hasLoaded = true
            readError = nil
        } catch {
            readError = error.localizedDescription
        }
    }

    func setProject(_ ids: [String], _ path: String) async {
        guard !ids.isEmpty else { return }
        await write(["library", "set"] + ids + ["--project", path])
    }

    func setStarred(_ ids: [String], _ on: Bool) async {
        guard !ids.isEmpty else { return }
        await write(["library", "set"] + ids + [on ? "--star" : "--unstar"])
    }

    func setTitle(_ id: String, _ title: String) async {
        await write(["library", "set", id, "--title", title])
    }

    func setNotes(_ id: String, _ notes: String) async {
        await write(["library", "set", id, "--notes", notes])
    }

    func forget(_ ids: [String]) async {
        guard !ids.isEmpty else { return }
        await write(["library", "forget"] + ids)
    }

    func relocate(_ id: String, to url: URL) async {
        await write(["library", "relocate", id, url.path])
    }

    func addFolder(_ path: String) async {
        await write(["library", "folder", "add", path])
    }

    func renameFolder(_ from: String, to: String) async {
        await write(["library", "folder", "rename", from, to])
    }

    func removeFolder(_ path: String) async {
        await write(["library", "folder", "remove", path])
    }

    /// Runs the CLI off the main actor, then reloads. A failure becomes `problem`.
    /// Writes run one at a time in the order they were asked for: the CLI
    /// rewrites library.json without a lock, so two at once could lose one.
    private func write(_ args: [String]) async {
        guard let cli else {
            problem = CLIError.notInstalled.message
            return
        }
        await writes.run { [weak self] in
            do {
                _ = try await cli.run(args)
                self?.problem = nil
                self?.reload()
            } catch let error as CLIError {
                self?.problem = error.message
            } catch {
                self?.problem = error.localizedDescription
            }
        }
    }
}
