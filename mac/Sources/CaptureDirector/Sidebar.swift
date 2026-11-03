import AppKit
import CaptureDirectorKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A folder dragged inside the sidebar. Only this app sees it (the provider is
    /// `.ownProcess`), so nothing outside ever gets a folder path where it wanted a file.
    static let captureFolder = UTType(exportedAs: "io.github.dhanson-wp.capture-director.folder")
}

/// The source list: the Library pages, then the project folders and Unsorted.
///
/// Folders are library-only. New folder (the + button, ⇧⌘N, or the context menu) adds one and
/// opens its name; double-click, Return, or Rename edits a name in place. Dragging a folder onto
/// another nests it, and onto the Projects header moves it to the top. Captures dragged from the
/// grid or list drop onto a folder or Unsorted. The drag carries only the videos' file URLs, the
/// same as a drag to Finder or an upload page, and the drop finds the captures by those files.
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    let library: Library
    @Binding var item: SidebarItem
    let now: Date

    /// Library pages, in sidebar order.
    static let libraryItems: [SidebarItem] = [.all, .recent, .starred, .finals, .clips]

    /// The count shown on each page's row. The self-test checks these against Browse.count.
    static func count(_ item: SidebarItem, in library: Library, now: Date) -> Int {
        Browse.count(library.entries, item: item, now: now)
    }

    var body: some View {
        let browser = model.browser
        let tree = FolderTree.build(library)
        let deletable = FolderEdit.deletable(tree)
        let selection = Binding<SidebarItem?>(get: { item }, set: { if let new = $0 { item = new } })
        List(selection: selection) {
            Section("Library") {
                ForEach(Self.libraryItems, id: \.self) { page in
                    row(page)
                }
            }
            Section {
                ForEach(tree) { node in
                    FolderRow(node: node)
                }
                row(.unsorted)
                    .dropTarget(model: model, path: "", folders: false)
            } header: {
                ProjectsHeader()
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: SidebarItem.self) { items in
            if items.count == 1, case .folder(let path)? = items.first {
                Button("New folder") { Task { await model.newFolder(in: path) } }
                Button("Rename") { browser.renamingFolder = path }
                Divider()
                Button("Delete folder") { Task { await model.deleteFolder(path) } }
                    .disabled(!deletable.contains(path))
            }
        } primaryAction: { items in
            // Double-click a folder to rename it.
            if items.count == 1, case .folder(let path)? = items.first { browser.renamingFolder = path }
        }
        .onKeyPress(.return) {
            guard browser.renamingFolder == nil, case .folder(let path) = item else { return .ignored }
            browser.renamingFolder = path
            return .handled
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
    }

    private func row(_ page: SidebarItem) -> some View {
        Label(page.title, systemImage: page.symbol)
            .badge(Self.count(page, in: library, now: now))
            .tag(page)
    }

    private var footer: some View {
        Label("Local only. Your videos stay where they were rendered.", systemImage: "lock")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)
    }
}

/// "Projects", with the + for a new folder. A folder dropped here moves to the top level.
private struct ProjectsHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            Text("Projects")
            Spacer()
            Button("New folder", systemImage: "plus") { Task { await model.newFolder() } }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("New folder (Shift-Command-N)")
        }
        .dropTarget(model: model, path: "", captures: false)
    }
}

/// One folder and, when it's open, the folders inside it.
private struct FolderRow: View {
    @Environment(AppModel.self) private var model
    let node: FolderNode

    var body: some View {
        let browser = model.browser
        if node.children.isEmpty {
            label
        } else {
            DisclosureGroup(isExpanded: Binding(get: { !browser.closedFolders.contains(node.path) },
                                                set: { open in
                                                    if open { browser.closedFolders.remove(node.path) }
                                                    else { browser.closedFolders.insert(node.path) }
                                                })) {
                ForEach(node.children) { child in
                    FolderRow(node: child)
                }
            } label: {
                label
            }
        }
    }

    @ViewBuilder private var label: some View {
        if model.browser.renamingFolder == node.path {
            Label {
                FolderNameField(path: node.path)
            } icon: {
                Image(systemName: "folder")
            }
            .tag(SidebarItem.folder(node.path))
        } else {
            Label(node.name, systemImage: "folder")
                .badge(node.count)
                .help(node.path)
                .tag(SidebarItem.folder(node.path))
                .onDrag {
                    model.browser.draggingFolder = node.path
                    let provider = NSItemProvider()
                    let data = Data(node.path.utf8)
                    provider.registerDataRepresentation(forTypeIdentifier: UTType.captureFolder.identifier,
                                                        visibility: .ownProcess) { @Sendable done in
                        done(data, nil)
                        return nil
                    }
                    provider.suggestedName = node.name
                    return provider
                }
                .dropTarget(model: model, path: node.path)
        }
    }
}

/// A folder's name, open for editing. Return saves, Escape puts the name back, and clicking
/// away saves too, like Finder. The CLI's refusals show in the window's banner.
private struct FolderNameField: View {
    @Environment(AppModel.self) private var model
    let path: String
    @State private var name = ""
    @State private var done = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Folder name", text: $name)
            .labelsHidden()
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit(commit)
            .onExitCommand(perform: cancel)
            .onChange(of: focused) { _, on in if !on { commit() } }
            .onAppear {
                name = FolderPath.name(path)
                Task {
                    focused = true
                    // Select the whole name, ready to type over.
                    try? await Task.sleep(for: .milliseconds(50))
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
            }
            // However the field goes (another rename started, a reload), a typed name is kept,
            // and only this field's own rename ends, never a newer one.
            .onDisappear(perform: commit)
    }

    private func commit() {
        guard !done else { return }
        done = true
        let target = FolderEdit.renameTarget(path, to: name)
        model.browser.endRename(path)
        if let target { Task { await model.renameFolder(path, to: target) } }
    }

    private func cancel() {
        done = true
        model.browser.endRename(path)
    }
}

extension View {
    /// Makes a sidebar row take dropped captures (moved into `path`, "" for Unsorted) and,
    /// for a folder row or the Projects header, dropped folders (nested under `path`).
    func dropTarget(model: AppModel, path: String, folders: Bool = true, captures: Bool = true) -> some View {
        modifier(DropTarget(model: model, path: path, folders: folders, captures: captures))
    }
}

/// A ring around the row while something it takes is over it.
private struct DropTarget: ViewModifier {
    let model: AppModel
    let path: String
    let folders: Bool
    let captures: Bool
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .strokeBorder(Palette.accent, lineWidth: 2)
                        .padding(-Space.xs)
                }
            }
            .onDrop(of: [.captureFolder, .fileURL],
                    delegate: FolderDrop(model: model, path: path, folders: folders, captures: captures,
                                         targeted: $targeted))
    }
}

/// What a drop on a sidebar row does. A folder can't go into itself or where it already is;
/// file URLs become captures by their paths, and files that aren't in the library are ignored.
struct FolderDrop: DropDelegate {
    let model: AppModel
    let path: String
    let folders: Bool
    let captures: Bool
    @Binding var targeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        if info.hasItemsConforming(to: [.captureFolder]) {
            guard folders, let dragged = model.browser.draggingFolder else { return false }
            return FolderEdit.moveTarget(dragged, into: path) != nil
        }
        return captures && info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) { targeted = validateDrop(info: info) }
    func dropExited(info: DropInfo) { targeted = false }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        guard validateDrop(info: info) else { return false }
        let model = model, path = path
        if info.hasItemsConforming(to: [.captureFolder]) {
            guard let provider = info.itemProviders(for: [.captureFolder]).first else { return false }
            // The callback comes on a background queue, so it mustn't inherit the main actor.
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.captureFolder.identifier) { @Sendable data, _ in
                guard let data, let from = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in await model.moveFolder(from, into: path) }
            }
            return true
        }
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { done in
                    _ = provider.loadObject(ofClass: URL.self) { @Sendable url, _ in done.resume(returning: url) }
                }
                if let url { urls.append(url) }
            }
            await model.dropCaptures(urls, on: path)
        }
        return true
    }
}
