import AppKit
import CaptureDirectorKit
import SwiftUI

/// Grid of cards or a table of rows.
enum Layout: String, CaseIterable, Identifiable {
    case grid, list
    var id: String { rawValue }
    var title: String { self == .grid ? "Grid" : "List" }
    var symbol: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
}

/// What the main window is showing. It lives on AppModel so the menu bar
/// commands and snapshot mode can drive it. Tasks 8 to 11 read and change it.
@MainActor
@Observable
final class Browser {
    var selection: Set<LibraryEntry.ID> = [] {
        didSet {
            // A selection made another way (the list, a reload) moves the ⇧-click anchor too.
            if selection.count == 1 { anchor = selection.first; cursor = selection.first }
            else if let a = anchor, !selection.contains(a) { anchor = nil }
            if selection.isEmpty { cursor = nil }
            MenuState.shared.update(self)
            QuickLook.shared.selectionChanged()
        }
    }
    /// The capture playing in the player sheet.
    var player: LibraryEntry? { didSet { MenuState.shared.update(self) } }
    /// A text field other than search is being edited: a folder name in the sidebar, or a
    /// field that some owner (the inspector, the New folder alert) said it's editing.
    /// Derived, so one edit ending can never free the keys while another is still typing.
    var editingText: Bool { renamingFolder != nil || !editors.isEmpty }
    /// Who's editing text right now, by name. Each owner adds and removes only itself.
    private(set) var editors: Set<String> = [] { didSet { MenuState.shared.update(self) } }
    /// Says that `owner` started or stopped editing text.
    func editing(_ owner: String, _ on: Bool) {
        if on { editors.insert(owner) } else { editors.remove(owner) }
    }
    /// Bare-key shortcuts (Space, Quick Look) are free: no text field is
    /// focused and no sheet is open. Anything that takes keys sets one of these.
    var keysFree: Bool { !searchFocused && !editingText && player == nil && confirmingRemove == nil }
    var item: SidebarItem = .all
    var search = ""
    var sort: CaptureDirectorKit.SortOrder = .newest { didSet { MenuState.shared.update(self) } }
    var layout: Layout = .grid {
        didSet {
            // The list keeps its own order; a range from the grid's anchor would be wrong there.
            if layout != oldValue { anchor = nil; cursor = nil }
            MenuState.shared.update(self)
        }
    }
    var showInspector = false
    /// Set by ⌘F; ContentView moves focus into the search field and clears it.
    var focusSearch = false
    var searchFocused = false { didSet { MenuState.shared.update(self) } }
    /// The last plain or ⌘-clicked capture, where a ⇧-click range starts.
    var anchor: LibraryEntry.ID?
    /// The card the arrow keys move from: the last one clicked or moved to.
    var cursor: LibraryEntry.ID?
    /// Starred captures and folder paths, kept by ContentView for the Capture menu.
    var starredIDs: Set<LibraryEntry.ID> = [] { didSet { MenuState.shared.update(self) } }
    var folderPaths: [String] = [] { didSet { MenuState.shared.update(self) } }
    /// Captures whose video isn't there, kept by ContentView. Space and Open need a file.
    var missingIDs: Set<LibraryEntry.ID> = [] { didSet { MenuState.shared.update(self) } }

    /// Remove from library (⌘⌫). ContentView sets it to ask first.
    var removeSelected: (() -> Void)? { didSet { MenuState.shared.update(self) } }
    /// The captures the Remove confirmation is asking about; nil when it isn't showing.
    var confirmingRemove: [LibraryEntry]? { didSet { MenuState.shared.update(self) } }
    /// New folder (⇧⌘N). ContentView sets it once the window is up.
    var newFolder: (() -> Void)? { didSet { MenuState.shared.update(self) } }
    /// The folder whose name is open for editing in the sidebar. Bare-key shortcuts step
    /// aside while it's set. Starting another rename replaces it; a field that's leaving
    /// calls `endRename(_:)` with its own path, so it never closes the newer one.
    var renamingFolder: String? { didSet { MenuState.shared.update(self) } }
    /// The rename of `path` is over, if it's still the one open.
    func endRename(_ path: String) {
        if renamingFolder == path { renamingFolder = nil }
    }
    /// Folders the person closed in the sidebar. Every folder starts open.
    var closedFolders: Set<String> = []
    /// The last rename or move this app asked for, so the sidebar can follow the folder.
    var lastRename: (from: String, to: String)?
    /// The folder being dragged in the sidebar, so a drop target can say no to a move into itself.
    var draggingFolder: String?

    /// A click on a card: plain selects only it, ⌘ adds or removes it,
    /// ⇧ selects the range from the anchor in the order on screen.
    func click(_ id: LibraryEntry.ID, in order: [LibraryEntry.ID], modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift), let anchor, let from = order.firstIndex(of: anchor),
           let to = order.firstIndex(of: id) {
            let range = Set(order[min(from, to)...max(from, to)])
            selection = modifiers.contains(.command) ? selection.union(range) : range
        } else if modifiers.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchor = id
        } else {
            selection = [id]
            anchor = id
        }
        cursor = id
    }

    /// An arrow key in the grid. It acts like a click on the card it lands on, so ⇧
    /// extends the selection from the anchor and ⌘ adds or removes that card.
    /// Returns false when the key isn't the grid's to take.
    @discardableResult
    func move(_ direction: GridMove.Direction, in order: [LibraryEntry.ID], columns: Int,
              modifiers: NSEvent.ModifierFlags) -> Bool {
        guard keysFree else { return false }
        // With no cursor (a selection made in the list), go on from the first selected card.
        let from = (cursor ?? order.first { selection.contains($0) }).flatMap { order.firstIndex(of: $0) }
        guard let to = GridMove.next(from: from, direction, count: order.count, columns: columns) else { return false }
        // ⇧ with nothing to extend from starts the range where the cursor is.
        if modifiers.contains(.shift), anchor == nil { anchor = from.map { order[$0] } ?? order[to] }
        click(order[to], in: order, modifiers: modifiers.intersection([.shift, .command]))
        return true
    }

    /// Select all (⌘A) in the grid: every capture on the page.
    @discardableResult
    func selectAll(_ order: [LibraryEntry.ID]) -> Bool {
        guard keysFree, !order.isEmpty else { return false }
        selection = Set(order)
        if anchor == nil { anchor = order.first }
        return true
    }
}

/// The menu bar's view of the browser. SwiftUI commands don't observe
/// @Observable models, so the App observes this and rebuilds the menus.
@MainActor
final class MenuState: ObservableObject {
    static let shared = MenuState()
    @Published private(set) var layout: Layout = .grid
    @Published private(set) var sort: CaptureDirectorKit.SortOrder = .newest
    @Published private(set) var canRemove = false
    @Published private(set) var canAddFolder = false
    @Published private(set) var canQuickLook = false
    @Published private(set) var canPlay = false
    /// Something is selected: the Capture menu's items apply.
    @Published private(set) var hasSelection = false
    /// Every selected capture is starred, so Star reads Unstar.
    @Published private(set) var allStarred = false
    @Published private(set) var folders: [String] = []

    func update(_ b: Browser) {
        if layout != b.layout { layout = b.layout }
        if sort != b.sort { sort = b.sort }
        // ⌘⌫ deletes text in the search field, so the menu item steps aside there.
        let remove = !b.selection.isEmpty && b.keysFree && b.removeSelected != nil
        if canRemove != remove { canRemove = remove }
        if canAddFolder != (b.newFolder != nil) { canAddFolder = b.newFolder != nil }
        // Space types a space in the search field, so Quick Look steps aside there.
        // A selection with no video to show (every one moved) has nothing to look at or play.
        let hasFile = !b.selection.isSubset(of: b.missingIDs)
        let look = !b.selection.isEmpty && hasFile && b.keysFree
        if canQuickLook != look { canQuickLook = look }
        let play = b.selection.count == 1 && hasFile && b.keysFree
        if canPlay != play { canPlay = play }
        if hasSelection != !b.selection.isEmpty { hasSelection = !b.selection.isEmpty }
        let starred = !b.selection.isEmpty && b.selection.isSubset(of: b.starredIDs)
        if allStarred != starred { allStarred = starred }
        if folders != b.folderPaths { folders = b.folderPaths }
    }
}

extension SidebarItem {
    /// The page's name in the sidebar and the window title.
    var title: String {
        switch self {
        case .all: "All captures"
        case .recent: "Recent"
        case .starred: "Starred"
        case .finals: "Final videos"
        case .clips: "Clips"
        case .unsorted: "Unsorted"
        case .folder(let path): FolderPath.name(path)
        }
    }

    var symbol: String {
        switch self {
        case .all: "film.stack"
        case .recent: "clock"
        case .starred: "star"
        case .finals: "checkmark.seal"
        case .clips: "scissors"
        case .unsorted: "tray"
        case .folder: "folder"
        }
    }
}

extension CaptureDirectorKit.SortOrder {
    var title: String {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .name: "Name"
        case .longest: "Longest"
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchFocus: Bool
    /// "Now" for Recent and the sidebar counts. It changes when the library
    /// reloads and once a minute, never on a click, so selecting doesn't redo the browse.
    @State private var now = Date()

    private var store: LibraryStore { model.store }

    var body: some View {
        @Bindable var browser = model.browser
        let entries = Browse.apply(store.library.entries, item: browser.item, search: browser.search,
                                   sort: browser.sort, now: now)
        NavigationSplitView {
            Sidebar(library: store.library, item: $browser.item, now: now)
                .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 320)
        } detail: {
            detail(entries)
                .navigationTitle(browser.item.title)
                .navigationSubtitle(entries.count == 1 ? "1 capture" : "\(entries.count) captures")
                .toolbar { toolbar }
                .safeAreaInset(edge: .top, spacing: 0) { banners }
                .safeAreaInset(edge: .bottom, spacing: 0) { skippedNote }
        }
        .inspector(isPresented: $browser.showInspector) {
            Inspector()
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
                .toolbar {
                    ToolbarSpacer(.flexible)
                    ToolbarItem {
                        Button("Inspector", systemImage: "sidebar.trailing") { browser.showInspector.toggle() }
                            .help("Show or hide the inspector (Control-Command-I)")
                    }
                }
        }
        .searchable(text: $browser.search, placement: .toolbar, prompt: "Search captures")
        .searchFocused($searchFocus)
        .onChange(of: browser.focusSearch) { _, on in
            if on { searchFocus = true; browser.focusSearch = false }
        }
        .onChange(of: searchFocus) { _, on in browser.searchFocused = on }
        .onChange(of: entries.map(\.id)) { _, ids in
            // A capture that left the page leaves the selection too.
            let keep = browser.selection.intersection(ids)
            if keep != browser.selection { browser.selection = keep }
        }
        .onChange(of: store.library, initial: true) {
            now = Date()
            browser.starredIDs = Set(store.library.entries.filter(\.starred).map(\.id))
            browser.folderPaths = FolderTree.paths(store.library)
            model.followFolder()
        }
        .onChange(of: store.missing, initial: true) { _, ids in browser.missingIDs = ids }
        .sheet(item: $browser.player) { entry in
            PlayerSheet(entry: entry)
        }
        .confirmationDialog(removeTitle(browser.confirmingRemove ?? []),
                            isPresented: Binding(get: { browser.confirmingRemove != nil },
                                                 set: { if !$0 { browser.confirmingRemove = nil } }),
                            presenting: browser.confirmingRemove) { entries in
            Button("Remove from library", role: .destructive) {
                Task { await model.remove(entries) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { entries in
            Text(entries.count == 1
                 ? "The video file stays where it is. You can add it back with capture-director library add."
                 : "The video files stay where they are. You can add them back with capture-director library add.")
        }
        .onAppear {
            browser.newFolder = { [weak model] in
                guard let model else { return }
                Task { await model.newFolder() }
            }
            browser.removeSelected = { [weak model] in
                guard let model else { return }
                let entries = model.selectedEntries()
                if !entries.isEmpty { model.browser.confirmingRemove = entries }
            }
        }
        .noInitialFocus()
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = Date()
            }
        }
        .task {
            store.start()
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model)
        }
    }

    @ViewBuilder
    private func detail(_ entries: [LibraryEntry]) -> some View {
        let browser = model.browser
        if let error = store.readError, !store.hasLoaded {
            ContentUnavailableView("Couldn't read the library", systemImage: "exclamationmark.triangle",
                                   description: Text(error))
        } else if store.library.entries.isEmpty {
            EmptyLibrary()
        } else if entries.isEmpty {
            if !browser.search.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView.search(text: browser.search)
            } else {
                ContentUnavailableView(emptyTitle(browser.item), systemImage: browser.item.symbol,
                                       description: Text(emptyDescription(browser.item)))
            }
        } else {
            switch browser.layout {
            case .grid: GridView(entries: entries)
            case .list: ListView(entries: entries)
            }
        }
    }

    private func removeTitle(_ entries: [LibraryEntry]) -> String {
        entries.count == 1 ? "Remove \u{201C}\(entries[0].title)\u{201D} from the library?"
                           : "Remove \(entries.count) captures from the library?"
    }

    private func emptyTitle(_ item: SidebarItem) -> String {
        switch item {
        case .starred: "No starred captures"
        case .recent: "Nothing from the last 7 days"
        case .finals: "No final videos"
        case .clips: "No clips"
        case .unsorted: "Everything's in a folder"
        case .all, .folder: "This folder is empty"
        }
    }

    private func emptyDescription(_ item: SidebarItem) -> String {
        switch item {
        case .starred: "Star the captures you come back to, and they'll gather here."
        case .recent: "Captures you add or change this week show up here."
        case .finals: "Videos you render from a timeline show up here."
        case .clips: "Shots you record show up here."
        case .unsorted: "Captures with no folder show up here."
        case .all, .folder: "Drag captures onto this folder to move them here."
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        @Bindable var browser = model.browser
        ToolbarItem(placement: .primaryAction) {
            Picker("Layout", selection: $browser.layout) {
                ForEach(Layout.allCases) { layout in
                    Label(layout.title, systemImage: layout.symbol).tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .help("Show captures as a grid (Command-1) or a list (Command-2)")
            .disabled(store.library.entries.isEmpty)
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            Menu("Sort", systemImage: "arrow.up.arrow.down") {
                Picker("Sort by", selection: $browser.sort) {
                    ForEach(CaptureDirectorKit.SortOrder.allCases, id: \.self) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.inline)
            }
            .help("Change the order of the captures")
            .disabled(store.library.entries.isEmpty)
        }
    }

    @ViewBuilder private var banners: some View {
        VStack(spacing: Space.sm) {
            if let error = store.readError, store.hasLoaded {
                Banner(text: "Couldn't read the library, so this is the last good copy. \(error)")
            }
            if let problem = store.problem {
                Banner(text: problem) { store.problem = nil }
            }
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, store.readError != nil && store.hasLoaded || store.problem != nil ? Space.sm : 0)
    }

    @ViewBuilder private var skippedNote: some View {
        let n = store.library.skipped
        if n > 0 {
            Text(n == 1 ? "1 capture couldn't be read from library.json." : "\(n) captures couldn't be read from library.json.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.sm)
        }
    }
}

/// A problem over the captures, with an optional close button.
private struct Banner: View {
    let text: String
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if let dismiss {
                Button("Dismiss", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Hide this message")
            }
        }
        .font(.callout)
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(.separator))
    }
}

/// The library has nothing in it: the three commands that fill it, each with a copy button.
private struct EmptyLibrary: View {
    private static let commands: [(note: String, text: String)] = [
        ("Record a shot list", "capture-director record shots.yaml"),
        ("Render a timeline", "capture-director render timeline.yaml"),
        ("Bring in videos you already have", "capture-director library add ~/Projects/demos"),
    ]

    var body: some View {
        ContentUnavailableView {
            Label("Nothing on the reel yet", systemImage: "film.stack")
        } description: {
            Text("Every clip from record and every video from render shows up here on its own, wherever you saved it. Run these in Terminal.")
        } actions: {
            VStack(alignment: .leading, spacing: Space.md) {
                ForEach(Self.commands, id: \.text) { command in
                    CommandRow(note: command.note, text: command.text)
                }
            }
            .frame(maxWidth: 520)
        }
    }
}

/// A command to paste into Terminal, with a line saying what it does and a copy button.
private struct CommandRow: View {
    let note: String
    let text: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(note)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: Space.sm) {
                Text(text)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Copy the command, to paste into Terminal")
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(.separator))
        }
    }
}
