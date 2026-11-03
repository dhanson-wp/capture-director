import AppKit
import CaptureDirectorKit
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
    @ObservedObject private var menu = MenuState.shared

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
            InspectorCommands()
            BrowserCommands(model: model, menu: menu)
        }

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

/// Menu bar items for browsing. Every toolbar control has one here too.
struct BrowserCommands: Commands {
    let model: AppModel
    @ObservedObject var menu: MenuState
    private var browser: Browser { model.browser }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New folder") { browser.newFolder?() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!menu.canAddFolder)
            Button("Play") {
                if let id = browser.selection.first,
                   let entry = model.store.library.entries.first(where: { $0.id == id }) { model.play(entry) }
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(!menu.canPlay)
            Button("Quick Look") { model.toggleQuickLook() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!menu.canQuickLook)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Remove from library…") { browser.removeSelected?() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!menu.canRemove)
        }
        CommandMenu("Capture") {
            Button(menu.allStarred ? "Unstar" : "Star") { model.toggleStar(model.selectedEntries()) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(!menu.hasSelection)
            Menu("Move to folder") {
                Button("Unsorted") { model.move(model.selectedEntries(), to: "") }
                if !menu.folders.isEmpty { Divider() }
                ForEach(menu.folders, id: \.self) { path in
                    Button(path) { model.move(model.selectedEntries(), to: path) }
                }
            }
            .disabled(!menu.hasSelection)
            Divider()
            Button("Copy video") { model.copyVideos(model.selectedEntries()) }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(!menu.hasSelection)
            Button("Copy for agent") { model.copyForAgent(model.selectedEntries()) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!menu.hasSelection)
            Button("Show in Finder") { model.showInFinder(model.selectedEntries()) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!menu.hasSelection)
        }
        CommandGroup(after: .textEditing) {
            Button("Search captures") { browser.focusSearch = true }
                .keyboardShortcut("f", modifiers: .command)
        }
        CommandGroup(before: .toolbar) {
            ForEach(Layout.allCases) { layout in
                Toggle(layout == .grid ? "As grid" : "As list",
                       isOn: Binding(get: { menu.layout == layout }, set: { _ in browser.layout = layout }))
                    .keyboardShortcut(layout == .grid ? "1" : "2", modifiers: .command)
            }
            Picker("Sort by", selection: Binding(get: { menu.sort }, set: { browser.sort = $0 })) {
                ForEach(CaptureDirectorKit.SortOrder.allCases, id: \.self) { order in
                    Text(order.title).tag(order)
                }
            }
            Divider()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Self-test and snapshot runs move and resize the window. This puts the
    /// saved frames and split-view widths back on quit, so a test run never
    /// changes how the app opens next time.
    private var windowDefaults: DefaultsGuard?

    func applicationWillFinishLaunching(_ notification: Notification) {
        if SelfTest.requested || Snapshot.requested {
            windowDefaults = DefaultsGuard(.standard, prefixes: ["NSWindow Frame", "NSSplitView Subview Frames",
                                                                 "NSToolbar Configuration"])
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if let windowDefaults {
            // Windows don't save frames after this; their autosave is off in these modes.
            for window in NSApp.windows { window.setFrameAutosaveName("") }
            windowDefaults.restore()
            UserDefaults.standard.synchronize()
        }
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}
