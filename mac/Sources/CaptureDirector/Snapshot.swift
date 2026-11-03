import AppKit
import CaptureDirectorKit
import IOKit.pwr_mgt
import SwiftUI

/// Screenshot mode for agents.
///   CD_HOME=/tmp/cd-test APP_SNAPSHOT=/tmp/shots "$HOME/Applications/Capture Director.app/Contents/MacOS/CaptureDirector"
/// writes <page>-light.png and <page>-dark.png for every page in `pages`, and
/// settings-<tab>-light.png and settings-<tab>-dark.png for every Settings tab, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// APP_SNAPSHOT_PAGES=all-grid,starred limits the pages (folder-rename shows a folder name being edited; inspector, inspector-multi, and inspector-tall show the inspector). Add "settings" to include Settings.
/// Add APP_ACCENT=<id> to see the pages in another accent.
enum Snapshot {
    /// One state of the main window: a name and how to get there from a fresh browser.
    struct Page {
        let name: String
        let show: @MainActor (AppModel) -> Void
    }

    static let pages: [Page] = [
        Page(name: "all-grid") { _ in },
        Page(name: "all-list") { $0.browser.layout = .list },
        Page(name: "folder") { $0.browser.item = .folder("blog/Post formats") },
        Page(name: "starred") { $0.browser.item = .starred },
        // An empty folder, and another one's name open for editing in place.
        Page(name: "folder-rename") { model in
            model.store.library.folders.append("Archive")
            model.browser.item = .folder("Spacefast")
            model.browser.renamingFolder = "Spacefast"
        },
        Page(name: "empty") { $0.store.library = Library() },
        // A clip with a source site and a shot list, so every section shows.
        Page(name: "inspector") { model in
            let entries = Browse.apply(model.store.library.entries, item: .all, search: "", sort: .newest, now: .now)
            let pick = entries.first { $0.title == "Gallery scroll" } ?? entries.first
            model.browser.selection = Set([pick?.id].compactMap { $0 })
            model.browser.showInspector = true
        },
        // A capture whose video is gone: the card, and the inspector's File moved section.
        // A capture with a finished web copy (snap.sh makes it first), so the Web copy section shows the result.
        Page(name: "inspector-copy") { model in
            let entries = Browse.apply(model.store.library.entries, item: .all, search: "", sort: .newest, now: .now)
            let pick = entries.first { $0.title == "Post formats tour" } ?? entries.first
            model.browser.selection = Set([pick?.id].compactMap { $0 })
            if let window = mainWindow, let screen = window.screen ?? NSScreen.main {
                var frame = window.frame
                frame.size.height = screen.visibleFrame.height
                frame.origin.y = screen.visibleFrame.minY
                window.setFrame(frame, display: true)
            }
            // After the resize has settled, or the inspector doesn't open in the second pass.
            Task {
                try? await Task.sleep(for: .seconds(0.3))
                model.browser.showInspector = true
            }
        },
        Page(name: "inspector-moved") { model in
            let entries = Browse.apply(model.store.library.entries, item: .all, search: "", sort: .newest, now: .now)
            let pick = entries.first { model.store.missing.contains($0.id) }
            model.browser.selection = Set([pick?.id].compactMap { $0 })
            model.browser.showInspector = true
        },
        Page(name: "inspector-multi") { model in
            let entries = Browse.apply(model.store.library.entries, item: .all, search: "", sort: .newest, now: .now)
            model.browser.selection = Set(entries.prefix(3).map(\.id))
            model.browser.showInspector = true
        },
        // The same clip in a window as tall as the screen, so the inspector's lower sections show.
        Page(name: "inspector-tall") { model in
            let entries = Browse.apply(model.store.library.entries, item: .all, search: "", sort: .newest, now: .now)
            let pick = entries.first { $0.title == "Gallery scroll" } ?? entries.first
            model.browser.selection = Set([pick?.id].compactMap { $0 })
            model.browser.showInspector = true
            if let window = mainWindow, let screen = window.screen ?? NSScreen.main {
                var frame = window.frame
                frame.size.height = screen.visibleFrame.height
                frame.origin.y = screen.visibleFrame.minY
                window.setFrame(frame, display: true)
            }
        },
    ]

    /// The main window's frame before any page changed it.
    private static var defaultFrame: NSRect?
    private static var mainWindow: NSWindow? { NSApp.windows.first { $0.canBecomeMain && !$0.isSheet } }

    /// Back to All captures in the grid with nothing selected, and the real library.
    private static func reset(_ model: AppModel, library: Library) async {
        let b = model.browser
        b.item = .all
        b.layout = .grid
        b.search = ""
        b.sort = .newest
        b.selection = []
        b.showInspector = false
        b.renamingFolder = nil
        if let window = mainWindow {
            if defaultFrame == nil { defaultFrame = window.frame }
            if let frame = defaultFrame, window.frame != frame { window.setFrame(frame, display: true) }
        }
        model.store.library = library
        await model.store.refreshMissing()
    }

    /// APP_SNAPSHOT is set: this run takes snapshots and quits.
    static var requested: Bool { !(ProcessInfo.processInfo.environment["APP_SNAPSHOT"] ?? "").isEmpty }

    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            // A sleeping display gives screencapture nothing. Declaring user
            // activity wakes it; the assertion keeps it on until the run quits.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            // Pages resize the window; keep that out of the frame the app reopens with.
            for window in NSApp.windows { window.setFrameAutosaveName("") }
            let library = model.store.library
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                for page in pages where only?.contains(page.name) ?? true {
                    await reset(model, library: library)
                    page.show(model)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/\(page.name)-\(mode).png")
                }
            }
            await reset(model, library: library)
            if only == nil || only?.contains("settings") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet }
                        capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings)
                    }
                }
            }
            print("SNAPSHOT done \(dir)")
            // An open sheet refuses terminate, and the run would wait forever.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    /// Captures the real window with screencapture, so glass, sidebars, and
    /// materials look exactly as on screen. That needs Screen Recording
    /// permission for the app that started this one (your terminal, or Claude).
    /// Without it, falls back to drawing the view hierarchy, which leaves
    /// sidebars and glass blank.
    private static func capture(to path: String, window: NSWindow? = nil) {
        // Another app can hide this one while snapshots run (computer use hides
        // apps it does not control). Hidden windows cannot be captured.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            print("SNAPSHOT no window")
            return
        }
        // Active, like a window someone is using: real accent colors and focus rings.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let size = window.contentView?.bounds.size ?? .zero
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }
}
