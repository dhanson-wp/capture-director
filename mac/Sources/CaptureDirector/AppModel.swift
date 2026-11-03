import CaptureDirectorKit
import Foundation
import Observation

/// What the windows share: the library store and which Settings tab is showing.
@MainActor
@Observable
final class AppModel {
    var settingsTab: SettingsTab = .general
    let store: LibraryStore

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
    }
}
