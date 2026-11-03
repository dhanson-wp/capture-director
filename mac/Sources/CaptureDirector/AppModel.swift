import Observation

/// What the windows share: which Settings tab is showing.
@MainActor
@Observable
final class AppModel {
    var settingsTab: SettingsTab = .general
}
