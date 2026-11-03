import CaptureDirectorKit
import SwiftUI

/// The source list: the Library pages, then the project folders and Unsorted.
struct Sidebar: View {
    let library: Library
    @Binding var item: SidebarItem
    let now: Date

    /// Library pages, in sidebar order.
    static let libraryItems: [SidebarItem] = [.all, .recent, .starred, .finals, .clips]

    /// The count shown on each page's row. The self-test checks these against Browse.count.
    static func count(_ item: SidebarItem, in library: Library, now: Date) -> Int {
        Browse.count(library.entries, item: item, now: now)
    }

    /// Folders that are open. Every folder starts open; closing one is remembered for the session.
    @State private var closed: Set<String> = []

    var body: some View {
        let selection = Binding<SidebarItem?>(get: { item }, set: { if let new = $0 { item = new } })
        List(selection: selection) {
            Section("Library") {
                ForEach(Self.libraryItems, id: \.self) { page in
                    row(page)
                }
            }
            Section("Projects") {
                ForEach(FolderTree.build(library)) { node in
                    FolderRow(node: node, closed: $closed)
                }
                row(.unsorted)
            }
        }
        .listStyle(.sidebar)
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

/// One folder and, when it's open, the folders inside it.
private struct FolderRow: View {
    let node: FolderNode
    @Binding var closed: Set<String>

    var body: some View {
        if node.children.isEmpty {
            label
        } else {
            DisclosureGroup(isExpanded: Binding(get: { !closed.contains(node.path) },
                                                set: { open in
                                                    if open { closed.remove(node.path) } else { closed.insert(node.path) }
                                                })) {
                ForEach(node.children) { child in
                    FolderRow(node: child, closed: $closed)
                }
            } label: {
                label
            }
        }
    }

    private var label: some View {
        Label(node.name, systemImage: "folder")
            .badge(node.count)
            .help(node.path)
            .tag(SidebarItem.folder(node.path))
    }
}
