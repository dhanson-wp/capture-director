import AppKit
import CaptureDirectorKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// What the windows share: the library store and what the main window is browsing.
@MainActor
@Observable
final class AppModel {
    let store: LibraryStore
    let browser = Browser()
    /// Poster and scrub frames, read from the same home as the library.
    let thumbnails: ThumbnailCache

    init() {
        var config: InstallConfig?
        if let url = Bundle.main.url(forResource: "config", withExtension: "json") {
            config = try? InstallConfig.load(from: url)
        }
        // One home for reads and writes: CD_HOME, else the config's cdHome, else the default.
        let home = InstallConfig.effectiveHome(env: ProcessInfo.processInfo.environment, configHome: config?.cdHome)
        let file = LibraryReader.file(cdHome: home)
        let cli = config.map { CLI(config: $0, home: file.deletingLastPathComponent()) }
        store = LibraryStore(file: file, cli: cli)
        thumbnails = ThumbnailCache(home: file.deletingLastPathComponent())
    }

    /// The selected captures in the order on screen.
    func selectedEntries() -> [LibraryEntry] {
        let b = browser
        return Browse.apply(store.library.entries, item: b.item, search: b.search, sort: b.sort, now: .now)
            .filter { b.selection.contains($0.id) }
    }

    /// The selected captures' videos in the order on screen, leaving out
    /// files that are gone. Quick Look, Copy video, and Show in Finder use these.
    func selectedURLs() -> [URL] {
        present(selectedEntries()).map(\.fileURL)
    }

    // Actions on the selection, shared by the inspector and the Capture menu.

    func copyVideos(_ entries: [LibraryEntry]) {
        let urls = present(entries).map(\.fileURL)
        if !urls.isEmpty { FileDrag.copy(urls) }
    }

    func copyForAgent(_ entries: [LibraryEntry]) {
        guard !entries.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(AgentBlock.text(for: entries), forType: .string)
    }

    func showInFinder(_ entries: [LibraryEntry]) {
        let urls = present(entries).map(\.fileURL)
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    /// Stars them all, or unstars them when every one is starred already.
    func toggleStar(_ entries: [LibraryEntry]) {
        let on = Bulk.starTarget(entries)
        Task { await store.setStarred(entries.map(\.id), on) }
    }

    /// "" is Unsorted.
    func move(_ entries: [LibraryEntry], to path: String) {
        Task { await store.setProject(entries.map(\.id), path) }
    }

    // Folders. Library-only: none of these touch a video file.

    /// New folder (⇧⌘N, the + button, or a folder's context menu): "New folder", or the next
    /// free number, inside `parent`, else the folder on screen, else at the top level.
    /// It's selected and its name opens for editing.
    func newFolder(in parent: String? = nil) async {
        let b = browser
        var parent = parent.map(FolderPath.normalize) ?? ""
        if parent.isEmpty, case .folder(let p) = b.item { parent = FolderPath.normalize(p) }
        let path = FolderEdit.newFolderPath(under: parent, existing: FolderTree.paths(store.library))
        await store.addFolder(path)
        guard FolderTree.paths(store.library).contains(path) else { return }
        b.closedFolders.remove(parent)
        b.item = .folder(path)
        b.renamingFolder = path
    }

    /// Renames or moves a folder, remembering it just long enough for the sidebar to follow it
    /// after the reload. Forgotten afterwards, so a refused rename, or a later delete, never
    /// sends the sidebar to the name it asked for.
    func renameFolder(_ from: String, to: String) async {
        browser.lastRename = (from, to)
        await store.renameFolder(from, to: to)
        followFolder()
        browser.lastRename = nil
    }

    /// A folder dropped on another, or on the Projects header (""). A drop that can't happen does nothing.
    func moveFolder(_ path: String, into target: String) async {
        guard let to = FolderEdit.moveTarget(path, into: target) else { return }
        browser.closedFolders.remove(target)
        await renameFolder(path, to: to)
    }

    /// Captures dropped on a folder ("" is Unsorted), found by their file URLs.
    /// Returns false when none of the files are in the library.
    @discardableResult
    func dropCaptures(_ urls: [URL], on path: String) async -> Bool {
        let all = FolderEdit.entryIDs(dropped: urls, in: store.library.entries)
        guard !all.isEmpty else { return false }
        let ids = FolderEdit.entryIDs(dropped: urls, in: store.library.entries, movingTo: path)
        await store.setProject(ids, path)
        return true
    }

    /// Delete folder, for a folder with nothing in it.
    func deleteFolder(_ path: String) async {
        await store.removeFolder(path)
        followFolder()
    }

    /// After a reload: a sidebar folder that's gone goes to its new path when this app just
    /// renamed it, else to All captures. ContentView calls this on every library change.
    func followFolder() {
        let b = browser
        let next = FolderEdit.fallback(b.item, paths: FolderTree.paths(store.library), renamed: b.lastRename)
        if next != b.item { b.item = next }
        if let r = b.renamingFolder, !FolderTree.paths(store.library).contains(r) { b.renamingFolder = nil }
    }

    /// Forgets the captures. The video files stay where they are.
    func remove(_ entries: [LibraryEntry]) async {
        await store.forget(entries.map(\.id))
    }

    /// Plays a capture in the player sheet. A video that's gone says so instead.
    func play(_ entry: LibraryEntry) {
        guard !store.missing.contains(entry.id) else {
            store.problem = "\(entry.title)'s video isn't at \(entry.file) anymore."
            return
        }
        browser.player = entry
    }

    /// Asks for the capture's new video, then points the entry at it. The CLI keeps the id
    /// and refuses a file another capture already uses; its message shows in the banner.
    func locate(_ entry: LibraryEntry) {
        let panel = NSOpenPanel()
        panel.title = "Locate \u{201C}\(entry.title)\u{201D}"
        panel.message = "Choose the video this capture should point to."
        panel.prompt = "Locate"
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .appleProtectedMPEG4Video]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: entry.file).deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let store = store, id = entry.id
        Task { await store.relocate(id, to: url) }
    }

    /// The captures whose video is there, by the store's last check (which the views watch).
    func present(_ entries: [LibraryEntry]) -> [LibraryEntry] {
        entries.filter { !store.missing.contains($0.id) }
    }

    func toggleQuickLook() {
        QuickLook.shared.toggle { [weak self] in self?.selectedURLs() ?? [] }
    }
}
