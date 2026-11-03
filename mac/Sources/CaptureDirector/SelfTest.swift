import AppKit
import CaptureDirectorKit

/// Self-test for agents: runs the app's real functions against a scratch library,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   CD_HOME=/tmp/CaptureDirector-self "$HOME/Applications/Capture Director.app/Contents/MacOS/CaptureDirector" --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            check("titles are cleaned", ItemTitle.clean("  Buy   milk ") == "Buy milk")
            await browsing(model)
            await thumbnails(model)
            await inspector(model)

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    /// The fixture from tools/fixture.sh: six captures in blog/Post formats, Spacefast, and Unsorted.
    private static func browsing(_ model: AppModel) async {
        let store = model.store
        let library = store.library
        let now = Date()
        check("the fixture library loads", library.entries.count == 6, "\(library.entries.count) entries")

        let expected: [(SidebarItem, Int)] = [(.all, 6), (.recent, 5), (.starred, 1), (.finals, 2), (.clips, 4), (.unsorted, 1)]
        for (item, n) in expected {
            let shown = Sidebar.count(item, in: library, now: now)
            let browse = Browse.count(library.entries, item: item, now: now)
            check("sidebar count for \(item.title) matches Browse.count", shown == browse && shown == n,
                  "sidebar \(shown), Browse \(browse), fixture \(n)")
        }

        let tree = FolderTree.build(library)
        let blog = tree.first { $0.path == "blog" }
        check("the folder tree has blog → Post formats",
              blog?.children.map(\.name) == ["Post formats"] && blog?.children.first?.path == "blog/Post formats",
              tree.map(\.path).description)
        func walk(_ nodes: [FolderNode]) -> [FolderNode] { nodes + nodes.flatMap { walk($0.children) } }
        let mismatched = walk(tree).filter { $0.count != Browse.count(library.entries, item: .folder($0.path), now: now) }
        check("every folder's count matches Browse.count", mismatched.isEmpty, mismatched.map(\.path).description)

        // Click, Command-click, and Shift-click in the grid.
        let b = Browser()
        let order = ["a", "b", "c", "d"]
        b.click("b", in: order, modifiers: [])
        check("a click selects one capture", b.selection == ["b"])
        b.click("d", in: order, modifiers: .command)
        check("Command-click adds a capture", b.selection == ["b", "d"])
        b.click("d", in: order, modifiers: .command)
        check("Command-click again removes it", b.selection == ["b"])
        b.click("b", in: order, modifiers: [])
        b.click("d", in: order, modifiers: .shift)
        check("Shift-click selects the range", b.selection == ["b", "c", "d"])

        // The menu bar has every browsing shortcut, once.
        func items(_ menu: NSMenu?) -> [NSMenuItem] {
            (menu?.items ?? []).flatMap { [$0] + items($0.submenu) }
        }
        let all = items(NSApp.mainMenu)
        func shortcut(_ key: String, _ mods: NSEvent.ModifierFlags) -> [NSMenuItem] {
            all.filter { $0.keyEquivalent == key && $0.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control]) == mods }
        }
        for (name, key, mods) in [("⌘F", "f", NSEvent.ModifierFlags.command), ("⌘1", "1", .command), ("⌘2", "2", .command),
                                  ("⌘⌫", "\u{8}", .command), ("⇧⌘N", "n", [.command, .shift])] {
            let found = shortcut(key, mods)
            check("the menu bar has \(name) once", found.count == 1, found.map(\.title).description)
        }

        // A failed change is a banner; it never turns into the can't-read screen.
        await store.setStarred(["0000000000000000"], true)
        check("a failed change shows as a problem, not a read error",
              store.problem != nil && store.readError == nil && store.library == library,
              "problem \(store.problem ?? "nil"), readError \(store.readError ?? "nil")")
        store.reload()
        check("a reload keeps the change's problem", store.problem != nil)
        check("the problem has no doubled prefix",
              store.problem.map { !$0.contains("Couldn't read the library") } ?? false, store.problem ?? "")
        store.problem = nil
    }

    /// Posters, scrub frames, the disk cache, and the deleted-file entry, on the fixture.
    private static func thumbnails(_ model: AppModel) async {
        let entries = model.store.library.entries
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("cd-thumbs-\(getpid())")
        defer { try? FileManager.default.removeItem(at: home) }
        let cache = ThumbnailCache(home: home)
        guard let tour = entries.first(where: { $0.title == "Post formats tour" }),
              let gone = entries.first(where: { $0.title == "Quote block" }),
              let pricing = entries.first(where: { $0.title == "Pricing toggle" }) else {
            check("the thumbnail fixtures are there", false)
            return
        }
        func bytes(_ image: CGImage?) -> Data? { image?.dataProvider?.data as Data? }

        let poster = await cache.image(for: tour, at: nil)
        check("a poster frame comes from the video, at most 640 wide",
              poster.map { $0.width > 0 && $0.width <= 640 } ?? false, "\(poster?.width ?? 0)")
        let early = await cache.image(for: tour, at: 0)
        let late = await cache.image(for: tour, at: 20)
        check("scrub frames at different times differ", early != nil && late != nil && bytes(early) != bytes(late))
        check("a repeat request comes back from memory", await cache.image(for: tour, at: 20) === late)
        check("a deleted video has no frame, and no crash", await cache.image(for: gone, at: nil) == nil)

        // The CLI's cached poster is used when it's newer than the video, and ignored when it's older.
        let thumbs = home.appendingPathComponent("thumbs")
        try? FileManager.default.createDirectory(at: thumbs, withIntermediateDirectories: true)
        let cached = thumbs.appendingPathComponent("\(pricing.id).jpg")
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 180, bitsPerSample: 8,
                                   samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        try? rep?.representation(using: .jpeg, properties: [:])?.write(to: cached)
        let fresh = await ThumbnailCache(home: home).image(for: pricing, at: nil)
        check("a fresh cached poster is used as it is", fresh?.width == 320, "\(fresh?.width ?? 0)")
        try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: cached.path)
        let stale = await ThumbnailCache(home: home).image(for: pricing, at: nil)
        check("a cached poster older than the video is skipped", stale.map { $0.width == 640 } ?? false, "\(stale?.width ?? 0)")

        // Quick Look gets the selection in screen order, without files that are gone.
        let b = model.browser
        b.selection = [tour.id, gone.id]
        check("Quick Look skips a deleted video", model.selectedURLs() == [tour.fileURL],
              model.selectedURLs().map(\.lastPathComponent).description)
        b.selection = [tour.id]
        let menu = MenuState.shared
        check("Quick Look and play are on with a selection and no sheet", menu.canQuickLook && menu.canPlay)
        b.player = tour
        check("Quick Look and play are off while the player is open", !menu.canQuickLook && !menu.canPlay)
        b.player = nil
        b.editingText = true
        check("Quick Look and play are off while a text field is being edited", !menu.canQuickLook && !menu.canPlay)
        b.editingText = false
        b.selection = []
    }

    /// The inspector, the Capture menu, Remove, the drag set, and real writes through the CLI.
    private static func inspector(_ model: AppModel) async {
        let b = model.browser
        let store = model.store
        let menu = MenuState.shared
        let entries = Browse.apply(store.library.entries, item: .all, search: "", sort: .newest, now: .now)
        guard entries.count >= 3, let gallery = entries.first(where: { $0.title == "Gallery scroll" }) else {
            check("the inspector fixtures are there", false)
            return
        }

        b.selection = [gallery.id]
        check("one selected capture shows its details", InspectorMode.of(model.selectedEntries()) == .one(gallery))
        b.selection = Set(entries.prefix(3).map(\.id))
        check("three selected show as several, in screen order",
              InspectorMode.of(model.selectedEntries()) == .several(Array(entries.prefix(3))))
        b.selection = []
        check("nothing selected shows nothing", InspectorMode.of(model.selectedEntries()) == .none)

        // Remove from library: on with a selection, asks first, and steps aside while typing.
        b.selection = [gallery.id]
        check("Remove from library is on with a selection", b.removeSelected != nil && menu.canRemove)
        b.editingText = true
        check("Remove from library is off while a text field is being edited", !menu.canRemove)
        b.editingText = false
        b.removeSelected?()
        check("Remove from library asks first, about the selection", b.confirmingRemove == [gallery])
        check("Space and Command-Delete are off while it asks", !menu.canRemove && !menu.canQuickLook)
        b.confirmingRemove = nil
        check("the menus have Copy video, Copy for agent, Show in Finder, and Star",
              menu.hasSelection && ["Copy video", "Copy for agent", "Show in Finder", "Star"].allSatisfy { title in
                  menuItems(NSApp.mainMenu).contains { $0.title == title }
              })

        // The drag set: the selection when the dragged capture is in it, else just that capture.
        let three = Array(entries.prefix(3))
        b.selection = Set(three.map(\.id))
        check("dragging a selected capture carries all three",
              DragSet.entries(dragging: three[1], selection: b.selection, in: entries) == three)
        let other = entries[3]
        check("dragging an unselected capture carries only it",
              DragSet.entries(dragging: other, selection: b.selection, in: entries) == [other])
        let existing = three.filter(\.fileExists)
        let items = FileDrag.dragItems(existing)
        check("a several-file drag has one item per video, each a file URL",
              items.count == existing.count && zip(items, existing).allSatisfy { ($0.item as? NSURL) as URL? == $1.fileURL },
              "\(items.count) items for \(existing.count) files")

        // The ⇧-click anchor follows a selection made in the list and resets on a layout switch.
        b.selection = [gallery.id]
        check("a single selection from anywhere becomes the anchor", b.anchor == gallery.id)
        b.layout = .list
        check("switching layout clears the anchor", b.anchor == nil)
        b.layout = .grid

        check("Record again quotes a shot list path with spaces",
              gallery.recordAgainCommand?.contains("'") == true && gallery.recordAgainCommand?.hasSuffix("--only gallery-scroll") == true,
              gallery.recordAgainCommand ?? "nil")

        // Real writes through the CLI on the scratch library.
        guard store.canWrite else {
            print("SKIP store writes: this build has no config.json, so it can't run the CLI")
            b.selection = []
            return
        }
        func current(_ id: String) -> LibraryEntry? { store.library.entries.first { $0.id == id } }
        await store.setStarred([gallery.id], true)
        check("Star writes through the CLI and the library reloads", current(gallery.id)?.starred == true, store.problem ?? "")
        await store.setStarred([gallery.id], false)
        await store.setTitle(gallery.id, "Gallery scroll, take two")
        check("a new title saves", current(gallery.id)?.title == "Gallery scroll, take two", store.problem ?? "")
        await store.setNotes(gallery.id, "Use this one on the launch post.")
        check("notes save", current(gallery.id)?.notes == "Use this one on the launch post.", store.problem ?? "")
        let ids = three.map(\.id)
        await store.setProject(ids, "Launch week")
        check("Move to folder moves all three into a new folder",
              ids.allSatisfy { current($0)?.folder == "Launch week" } && FolderTree.paths(store.library).contains("Launch week"),
              store.problem ?? "")
        let before = store.library.entries.count
        let gone = entries.last!
        let had = gone.fileExists
        await model.remove([gone])
        check("Remove from library forgets the capture and leaves its file alone",
              store.library.entries.count == before - 1 && current(gone.id) == nil
                  && FileManager.default.fileExists(atPath: gone.file) == had,
              store.problem ?? "")
        b.selection = []
    }

    private static func menuItems(_ menu: NSMenu?) -> [NSMenuItem] {
        (menu?.items ?? []).flatMap { [$0] + menuItems($0.submenu) }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
