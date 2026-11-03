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
            // The self-test stars, retitles, moves, and forgets captures. Never on the real library.
            if LibraryHome.isReal(model.store.home.path) {
                print("SELFTEST FAIL refusing to run on the real library at \(model.store.home.path). "
                      + "Set CD_HOME to a folder in /tmp, or use tools/selftest.sh.")
                finish(code: 1)
                return
            }
            for window in NSApp.windows { window.setFrameAutosaveName("") }
            try? await Task.sleep(for: .seconds(0.5))
            check("titles are cleaned", ItemTitle.clean("  Buy   milk ") == "Buy milk")
            await browsing(model)
            await thumbnails(model)
            await moved(model)
            await inspector(model)
            await folders(model)

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
        b.editing("selftest", true)
        check("Quick Look and play are off while a text field is being edited", !menu.canQuickLook && !menu.canPlay)
        b.editing("selftest", false)
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
        b.editing("selftest", true)
        check("Remove from library is off while a text field is being edited", !menu.canRemove)
        b.editing("selftest", false)
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
        let existing = model.present(three)
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
        // A web copy lands in the home's exports folder, smaller, and a second ask reuses it.
        if let copy = await store.exportCopy(gallery.id, preset: "web") {
            let original = (try? FileManager.default.attributesOfItem(atPath: gallery.file))?[.size] as? Int ?? 0
            check("a web copy is a smaller file under the home's exports folder",
                  copy.url.path == ExportCopy.file(home: store.home, id: gallery.id, preset: "web").path
                      && FileManager.default.fileExists(atPath: copy.file) && copy.size > 0 && copy.size < original,
                  "copy \(copy.size), original \(original)")
            check("the original is untouched by a copy", FileManager.default.fileExists(atPath: gallery.file))
            let again = await store.exportCopy(gallery.id, preset: "web")
            check("a second web copy is reused", again?.reused == true)
        } else {
            check("a web copy is made", false, store.problem ?? "")
        }
        // A copy in progress, and the same state read again after the inspector is gone and back.
        let slow = Task { await store.exportCopy(gallery.id, preset: "small") }
        await Task.yield()
        check("a copy in progress shows as making", store.exportJob(for: gallery.id)?.making == true)
        let joined = await store.exportCopy(gallery.id, preset: "small")
        let finished = await slow.value
        check("a second ask joins the first and gets the same file", joined != nil && joined == finished, store.problem ?? "")
        check("the finished copy is kept for a rebuilt inspector",
              store.exportJob(for: gallery.id)?.result?.preset == "small" && store.exportJob(for: gallery.id)?.making == false)
        check("a copy of an unknown capture fails with a problem", await store.export("nope", preset: "web") == nil && store.problem != nil)
        store.problem = nil
        // Two writes handed in at once both land, in order: the second waits for the first.
        let first = Task { await store.setTitle(gallery.id, "First title") }
        let second = Task { await store.setNotes(gallery.id, "Second, after the title.") }
        _ = await (first.value, second.value)
        check("two writes at once both land",
              current(gallery.id)?.title == "First title" && current(gallery.id)?.notes == "Second, after the title.",
              "title \(current(gallery.id)?.title ?? "nil"), notes \(current(gallery.id)?.notes ?? "nil")")
        let ids = three.map(\.id)
        await store.setProject(ids, "Launch week")
        check("Move to folder moves all three into a new folder",
              ids.allSatisfy { current($0)?.folder == "Launch week" } && FolderTree.paths(store.library).contains("Launch week"),
              store.problem ?? "")
        let before = store.library.entries.count
        let gone = entries.last!
        let had = FileManager.default.fileExists(atPath: gone.file)
        await model.remove([gone])
        check("Remove from library forgets the capture and leaves its file alone",
              store.library.entries.count == before - 1 && current(gone.id) == nil
                  && FileManager.default.fileExists(atPath: gone.file) == had,
              store.problem ?? "")
        b.selection = []
    }

    /// A capture whose file is gone: flagged, nothing to drag, look at, or play, and Locate puts it back with the same id.
    private static func moved(_ model: AppModel) async {
        let store = model.store
        let b = model.browser
        let menu = MenuState.shared
        guard let quote = store.library.entries.first(where: { $0.title == "Quote block" }),
              let tour = store.library.entries.first(where: { $0.title == "Post formats tour" }),
              let gallery = store.library.entries.first(where: { $0.title == "Gallery scroll" }) else {
            check("the moved-file fixtures are there", false)
            return
        }
        await store.refreshMissing()
        check("the deleted fixture video is flagged missing, and the others aren't",
              store.missing == [quote.id], store.missing.sorted().description)

        // Only the missing capture selected: nothing to drag, look at, or play.
        b.missingIDs = store.missing
        b.selection = [quote.id]
        check("Quick Look and play are off for a selection with no file", !menu.canQuickLook && !menu.canPlay)
        check("a missing capture has no URLs for Quick Look, Copy video, or Show in Finder",
              model.selectedURLs().isEmpty)
        check("drag has nothing to carry for a missing capture", model.present([quote]).isEmpty)
        b.selection = [quote.id, tour.id]
        check("Quick Look is on when the selection has a present file; play needs exactly one",
              menu.canQuickLook && !menu.canPlay)
        b.selection = []

        guard store.canWrite else {
            print("SKIP relocate: this build has no config.json, so it can't run the CLI")
            return
        }
        // A fresh video, made with ffmpeg in the scratch home.
        let fresh = store.home.appendingPathComponent("videos/moved/quote-block-new.mp4")
        try? FileManager.default.createDirectory(at: fresh.deletingLastPathComponent(), withIntermediateDirectories: true)
        let ffmpeg = Process()
        ffmpeg.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        ffmpeg.arguments = ["ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=640x360:rate=10",
                            "-t", "2", "-pix_fmt", "yuv420p", fresh.path]
        try? ffmpeg.run()
        ffmpeg.waitUntilExit()
        guard FileManager.default.fileExists(atPath: fresh.path) else {
            check("ffmpeg made a replacement video", false)
            return
        }

        // Refused: another capture's file. Nothing changes.
        await store.relocate(quote.id, to: gallery.fileURL)
        check("Locate refuses a video another capture already uses",
              store.problem?.contains("already in the library") == true && store.missing == [quote.id],
              store.problem ?? "no message")
        store.problem = nil
        // Refused: not a video the CLI accepts.
        let note = store.home.appendingPathComponent("videos/moved/notes.txt")
        try? "not a video".write(to: note, atomically: true, encoding: .utf8)
        await store.relocate(quote.id, to: note)
        check("Locate refuses a file that isn't a video", store.problem != nil && store.missing == [quote.id],
              store.problem ?? "no message")
        store.problem = nil

        await store.relocate(quote.id, to: fresh)
        let after = store.library.entries.first { $0.id == quote.id }
        check("Locate points the capture at the new file, keeping its id and title",
              after?.file == fresh.path && after?.title == "Quote block", store.problem ?? after?.file ?? "gone")
        check("the capture isn't missing anymore", store.missing.isEmpty, store.missing.sorted().description)
        b.missingIDs = store.missing
        b.selection = [quote.id]
        check("Quick Look and play come back with the file", menu.canQuickLook && menu.canPlay)
        b.selection = []
    }

    /// New folder, rename in place, nesting, dropping captures, and Delete folder, with real CLI writes.
    private static func folders(_ model: AppModel) async {
        let store = model.store
        let b = model.browser
        let menu = MenuState.shared
        check("New folder (Shift-Command-N) is on", menu.canAddFolder)
        guard store.canWrite else {
            print("SKIP folders: this build has no config.json, so it can't run the CLI")
            return
        }
        guard let pricing = store.library.entries.first(where: { $0.title == "Pricing toggle" }) else {
            check("the folder fixtures are there", false)
            return
        }
        func paths() -> [String] { FolderTree.paths(store.library) }
        func folder(_ id: String) -> String? { store.library.entries.first { $0.id == id }?.folder }
        // Let ContentView see the reload, the way it does after any write.
        func settle() async { try? await Task.sleep(for: .milliseconds(300)) }
        store.problem = nil

        b.item = .all
        await model.newFolder()
        // Selected right after, before the folder page drops it from the selection.
        b.selection = [pricing.id]
        check("New folder at the top level is called New folder, selected, and open for its name",
              paths().contains("New folder") && b.item == .folder("New folder") && b.renamingFolder == "New folder",
              "\(paths()) item \(b.item) renaming \(b.renamingFolder ?? "nil") \(store.problem ?? "")")
        check("Space, Command-O, and Command-Delete step aside while a folder name is edited",
              b.editingText && !menu.canQuickLook && !menu.canPlay && !menu.canRemove)
        b.renamingFolder = nil
        check("leaving the name gives the keys back", !b.editingText && menu.canQuickLook)

        // Starting a second rename while the first is open: the first field's exit
        // (its own endRename) leaves the second open and the keys still blocked.
        b.renamingFolder = "Spacefast"
        b.renamingFolder = "New folder"
        b.endRename("Spacefast")
        check("renaming B while A is open keeps B open and the keys blocked",
              b.renamingFolder == "New folder" && b.editingText && !menu.canQuickLook && !menu.canRemove,
              "renaming \(b.renamingFolder ?? "nil")")
        // An inspector field and a folder name each own their part: one ending doesn't free the other.
        b.editing("inspector", true)
        b.endRename("New folder")
        check("a folder name ending leaves the inspector's typing alone", b.renamingFolder == nil && b.editingText && !menu.canQuickLook)
        b.renamingFolder = "New folder"
        b.editing("inspector", false)
        check("the inspector ending leaves a folder name being edited alone", b.editingText && !menu.canQuickLook)
        b.endRename("New folder")
        check("with both done, the keys come back", !b.editingText && menu.canQuickLook)
        b.selection = []

        b.item = .all
        await model.newFolder()
        b.renamingFolder = nil
        check("the next one is New folder 2", paths().contains("New folder 2") && b.item == .folder("New folder 2"),
              paths().description)
        await model.newFolder()
        b.renamingFolder = nil
        check("New folder inside a selected folder goes in it",
              paths().contains("New folder 2/New folder") && b.item == .folder("New folder 2/New folder"),
              paths().description)
        await model.deleteFolder("New folder 2/New folder")

        guard let target = FolderEdit.renameTarget("New folder 2", to: "Drafts") else {
            check("a rename target", false)
            return
        }
        b.item = .folder("New folder 2")
        await model.renameFolder("New folder 2", to: target)
        check("rename in place changes the folder and the sidebar follows it",
              paths().contains("Drafts") && !paths().contains("New folder 2") && b.item == .folder("Drafts"),
              "\(paths()) item \(b.item) \(store.problem ?? "")")

        await model.moveFolder("Drafts", into: "New folder")
        check("dropping a folder on another nests it, and the sidebar follows",
              paths().contains("New folder/Drafts") && !paths().contains("Drafts") && b.item == .folder("New folder/Drafts"),
              "\(paths()) item \(b.item) \(store.problem ?? "")")
        await model.moveFolder("New folder/Drafts", into: "")
        check("dropping a folder on the Projects header moves it to the top level",
              paths().contains("Drafts") && b.item == .folder("Drafts"), "\(paths()) item \(b.item)")

        await model.renameFolder("Drafts", to: "Spacefast")
        check("a refused rename shows the CLI's message and changes nothing",
              store.problem == "There's already a folder called Spacefast" && paths().contains("Drafts") && b.item == .folder("Drafts"),
              "\(store.problem ?? "no message") item \(b.item)")
        store.problem = nil

        // Captures dropped on a folder arrive as the same file URLs a drag to Finder carries.
        let several = FileDrag.dragItems(model.present([pricing])).compactMap { ($0.item as? NSURL) as URL? }
        check("the drag-out payload maps back to the dragged captures",
              FolderEdit.entryIDs(dropped: several, in: store.library.entries) == [pricing.id])
        // Finder can hand over /private/tmp for a file the library has under /tmp.
        let linked = URL(fileURLWithPath: "/private" + pricing.file)
        let moved = await model.dropCaptures([linked], on: "Drafts")
        check("dropping a capture's file on a folder moves the capture there", moved && folder(pricing.id) == "Drafts",
              "\(folder(pricing.id) ?? "gone") \(store.problem ?? "")")
        check("the video file stays where it was", FileManager.default.fileExists(atPath: pricing.file))
        let stranger = await model.dropCaptures([URL(fileURLWithPath: "/tmp/not-in-the-library.mp4")], on: "Drafts")
        check("a file that isn't in the library isn't taken", !stranger)

        check("a folder with a capture in it can't be deleted",
              !FolderEdit.deletable(FolderTree.build(store.library)).contains("Drafts"))
        await store.removeFolder("Drafts")
        check("the CLI refuses it too", store.problem == "Drafts isn't empty" && paths().contains("Drafts"),
              store.problem ?? "no message")
        store.problem = nil

        await model.dropCaptures([pricing.fileURL], on: "")
        check("dropping on Unsorted takes the capture out of its folder", folder(pricing.id) == "", folder(pricing.id) ?? "gone")
        check("an empty folder can be deleted", FolderEdit.deletable(FolderTree.build(store.library)).contains("Drafts"))
        b.item = .folder("Drafts")
        await model.deleteFolder("Drafts")
        check("Delete folder removes it, and the sidebar goes to All captures",
              !paths().contains("Drafts") && b.item == .all, "\(paths()) item \(b.item) \(store.problem ?? "")")

        // Renamed somewhere else (the CLI in Terminal): the app didn't do it, so All captures.
        b.item = .folder("New folder")
        b.lastRename = nil
        await store.renameFolder("New folder", to: "Renamed elsewhere")
        await settle()
        check("a folder renamed outside the app falls back to All captures", b.item == .all, "item \(b.item)")
        await store.removeFolder("Renamed elsewhere")
        b.item = .all
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
