import AppKit
import CaptureDirectorKit
import Foundation
import Observation

/// What the windows share: the library store, what the main window is
/// browsing, and which Settings tab is showing.
@MainActor
@Observable
final class AppModel {
    var settingsTab: SettingsTab = .general
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
        selectedEntries().filter(\.fileExists).map(\.fileURL)
    }

    // Actions on the selection, shared by the inspector and the Capture menu.

    func copyVideos(_ entries: [LibraryEntry]) {
        let urls = entries.filter(\.fileExists).map(\.fileURL)
        if !urls.isEmpty { FileDrag.copy(urls) }
    }

    func copyForAgent(_ entries: [LibraryEntry]) {
        guard !entries.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(AgentBlock.text(for: entries), forType: .string)
    }

    func showInFinder(_ entries: [LibraryEntry]) {
        let urls = entries.filter(\.fileExists).map(\.fileURL)
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

    /// Forgets the captures. The video files stay where they are.
    func remove(_ entries: [LibraryEntry]) async {
        await store.forget(entries.map(\.id))
    }

    /// Plays a capture in the player sheet. A video that's gone says so instead.
    func play(_ entry: LibraryEntry) {
        guard FileManager.default.fileExists(atPath: entry.file) else {
            store.problem = "\(entry.title)'s video isn't at \(entry.file) anymore."
            return
        }
        browser.player = entry
    }

    func toggleQuickLook() {
        QuickLook.shared.toggle { [weak self] in self?.selectedURLs() ?? [] }
    }
}

extension LibraryEntry {
    /// The video is still at its path. Drag, Share, and Copy need it.
    var fileExists: Bool { FileManager.default.fileExists(atPath: file) }
}
