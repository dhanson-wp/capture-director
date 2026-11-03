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

    /// The selected captures' videos in the order on screen, leaving out
    /// files that are gone. Quick Look shows these.
    func selectedURLs() -> [URL] {
        let b = browser
        return Browse.apply(store.library.entries, item: b.item, search: b.search, sort: b.sort, now: .now)
            .filter { b.selection.contains($0.id) && FileManager.default.fileExists(atPath: $0.file) }
            .map(\.fileURL)
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
