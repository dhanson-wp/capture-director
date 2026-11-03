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
    var selection: Set<LibraryEntry.ID> = [] { didSet { MenuState.shared.update(self) } }
    var item: SidebarItem = .all
    var search = ""
    var sort: CaptureDirectorKit.SortOrder = .newest { didSet { MenuState.shared.update(self) } }
    var layout: Layout = .grid { didSet { MenuState.shared.update(self) } }
    var showInspector = false
    /// Set by ⌘F; ContentView moves focus into the search field and clears it.
    var focusSearch = false
    var searchFocused = false { didSet { MenuState.shared.update(self) } }
    /// The last plain or ⌘-clicked capture, where a ⇧-click range starts.
    var anchor: LibraryEntry.ID?

    /// Remove from library (⌘⌫). Task 9 sets it; until then the menu item is off.
    var removeSelected: (() -> Void)? { didSet { MenuState.shared.update(self) } }
    /// New folder (⇧⌘N). Task 11 sets it; until then the menu item is off.
    var newFolder: (() -> Void)? { didSet { MenuState.shared.update(self) } }

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

    func update(_ b: Browser) {
        if layout != b.layout { layout = b.layout }
        if sort != b.sort { sort = b.sort }
        // ⌘⌫ deletes text in the search field, so the menu item steps aside there.
        let remove = !b.selection.isEmpty && !b.searchFocused && b.removeSelected != nil
        if canRemove != remove { canRemove = remove }
        if canAddFolder != (b.newFolder != nil) { canAddFolder = b.newFolder != nil }
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
    @Environment(\.openSettings) private var openSettings
    @FocusState private var searchFocus: Bool

    private var store: LibraryStore { model.store }

    var body: some View {
        @Bindable var browser = model.browser
        let now = Date()
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
            InspectorPlaceholder(entries: store.library.entries.filter { browser.selection.contains($0.id) })
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
        .noInitialFocus()
        .task {
            store.start()
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    @ViewBuilder
    private func detail(_ entries: [LibraryEntry]) -> some View {
        let browser = model.browser
        if let error = store.readError, !store.hasLoaded {
            ContentUnavailableView("Couldn't read the library", systemImage: "exclamationmark.triangle",
                                   description: Text(error))
        } else if store.library.entries.isEmpty {
            ContentUnavailableView {
                Label("No captures yet", systemImage: "film.stack")
            } description: {
                // Non-breaking hyphens keep the command on one line.
                Text("Videos you record or render show up here. To bring in older ones, run \(Text("capture\u{2011}director library add <folder>").monospaced()) in Terminal.")
            }
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

/// Stands in for the inspector until Task 9 builds it.
private struct InspectorPlaceholder: View {
    let entries: [LibraryEntry]

    var body: some View {
        if entries.count == 1, let entry = entries.first {
            Form {
                Section {
                    LabeledContent("Kind", value: entry.isFinal ? "Final video" : "Clip")
                    if let d = entry.duration { LabeledContent("Length", value: Format.length(d)) }
                    if let w = entry.width, let h = entry.height { LabeledContent("Resolution", value: "\(w) × \(h)") }
                    if let s = entry.size { LabeledContent("Size", value: Format.size(s)) }
                } header: {
                    Text(entry.title).font(.headline)
                }
            }
            .formStyle(.grouped)
        } else if entries.count > 1 {
            ContentUnavailableView("\(entries.count) captures", systemImage: "square.stack",
                                   description: Text("Selected together."))
        } else {
            ContentUnavailableView("No selection", systemImage: "sidebar.trailing",
                                   description: Text("Select a capture to see its details."))
        }
    }
}
