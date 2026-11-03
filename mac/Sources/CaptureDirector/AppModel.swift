import CaptureDirectorKit
import Foundation
import Observation

/// What the windows share: the library and which Settings tab is showing.
@MainActor
@Observable
final class AppModel {
    var settingsTab: SettingsTab = .general
    var library = Library()
    var loadError: String?

    /// The library home: CD_HOME if set, else the bundled config's cdHome, else the default.
    static func libraryFile() -> URL {
        var configHome: String?
        if let url = Bundle.main.url(forResource: "config", withExtension: "json"),
           let config = try? InstallConfig.load(from: url) {
            configHome = config.cdHome
        }
        let home = InstallConfig.effectiveHome(env: ProcessInfo.processInfo.environment, configHome: configHome)
        return LibraryReader.file(cdHome: home)
    }

    func load() {
        do {
            library = try LibraryReader.load(from: Self.libraryFile())
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}
