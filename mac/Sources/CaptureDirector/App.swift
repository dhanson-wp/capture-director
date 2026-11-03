import AppKit
import SwiftUI

// CaptureDirector
//   CaptureDirector                      the app
//   APP_SNAPSHOT=<dir> CaptureDirector   save a PNG of the main window and every Settings tab in light and dark mode, then quit
//   CaptureDirector --selftest           run the self-test on a scratch library and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> CaptureDirector      run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 CaptureDirector           draw the 8 pt grid and the layout probes over the window

@main
struct CaptureDirectorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Capture Director", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 1100, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
        }

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}
