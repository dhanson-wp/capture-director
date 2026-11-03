import Foundation

/// Calls back (debounced) when anything in the folder holding `library.json` changes.
/// Watches the folder, not the file: the CLI replaces the file by rename, and a
/// watch on the old file would go quiet.
public final class LibraryWatcher: @unchecked Sendable {
    private let folder: URL
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "capture-director.library-watcher")
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    public init(file: URL, onChange: @escaping @Sendable () -> Void) {
        self.folder = file.deletingLastPathComponent()
        self.onChange = onChange
    }

    deinit { stop() }

    /// Creates the folder if it's missing, then starts watching it.
    public func start() {
        queue.sync {
            guard source == nil else { return }
            // Private, like the CLI makes it: the library lists every capture's path and notes.
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            let fd = open(folder.path, O_EVTONLY)
            guard fd >= 0 else { return }
            let s = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend, .attrib, .link], queue: queue)
            s.setEventHandler { [weak self] in self?.schedule() }
            s.setCancelHandler { close(fd) }
            source = s
            s.resume()
        }
    }

    public func stop() {
        queue.sync {
            pending?.cancel()
            pending = nil
            source?.cancel()
            source = nil
        }
    }

    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [onChange] in onChange() }
        pending = item
        queue.asyncAfter(deadline: .now() + .milliseconds(150), execute: item)
    }
}
