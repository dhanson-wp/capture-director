import Foundation

/// The rules behind making, renaming, nesting, and deleting folders in the sidebar,
/// and dropping captures on them. The CLI makes every change; these only work out what to ask for.
public enum FolderEdit {
    /// The folder a path sits in; "" for the top level.
    public static func parent(_ path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }

    private static func join(_ parent: String, _ name: String) -> String {
        FolderPath.normalize(parent.isEmpty ? name : parent + "/" + name)
    }

    /// "New folder", or "New folder 2" and so on, the first that's free inside `parent`.
    /// A name that differs only in case counts as taken.
    public static func newFolderPath(under parent: String, existing: [String]) -> String {
        let taken = Set(existing.filter { Self.parent($0) == parent }.map { FolderPath.name($0).lowercased() })
        var n = 1
        while true {
            let name = n == 1 ? "New folder" : "New folder \(n)"
            if !taken.contains(name.lowercased()) { return join(parent, name) }
            n += 1
        }
    }

    /// The path a folder gets when its name is edited in place: same parent, new name.
    /// nil when there's nothing to do (an empty name, or the name it already has).
    public static func renameTarget(_ path: String, to newName: String) -> String? {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != FolderPath.name(path) else { return nil }
        let target = join(parent(path), name)
        return target.isEmpty || target == path ? nil : target
    }

    /// The path a folder gets when it's dropped on `target` ("" is the Projects header, the top level).
    /// nil when the drop can't happen: onto itself, into a folder below it, or where it already is.
    public static func moveTarget(_ path: String, into target: String) -> String? {
        guard !path.isEmpty, !FolderPath.contains(path, target), parent(path) != target else { return nil }
        return join(target, FolderPath.name(path))
    }

    /// The captures behind dropped file URLs, matched on the entry's `file` path, in dropped order,
    /// once each. Files that aren't in the library are left out. With `movingTo`, captures already
    /// in that folder are left out too ("" is Unsorted).
    public static func entryIDs(dropped urls: [URL], in entries: [LibraryEntry], movingTo folder: String? = nil) -> [String] {
        var byPath: [String: LibraryEntry] = [:]
        for entry in entries { byPath[entry.fileURL.standardizedFileURL.path] = entry }
        var resolved: [String: LibraryEntry]?
        var out: [String] = []
        for url in urls where url.isFileURL {
            var entry = byPath[url.standardizedFileURL.path]
            if entry == nil {
                // /tmp and /private/tmp, or a linked folder: compare the real paths, built only when needed.
                if resolved == nil {
                    resolved = [:]
                    for e in entries { resolved?[e.fileURL.resolvingSymlinksInPath().path] = e }
                }
                entry = resolved?[url.resolvingSymlinksInPath().path]
            }
            guard let entry, !out.contains(entry.id) else { continue }
            if let folder, entry.folder == FolderPath.normalize(folder) { continue }
            out.append(entry.id)
        }
        return out
    }

    /// Folders with nothing in them or below them. Only these offer Delete folder.
    public static func deletable(_ tree: [FolderNode]) -> Set<String> {
        var out = Set<String>()
        func walk(_ nodes: [FolderNode]) {
            for node in nodes {
                if node.count == 0 { out.insert(node.path) }
                walk(node.children)
            }
        }
        walk(tree)
        return out
    }

    /// Where the sidebar goes when its folder isn't in `paths` anymore: to the folder's new
    /// path when this app just renamed it (or a folder above it), else to All captures.
    public static func fallback(_ item: SidebarItem, paths: [String], renamed: (from: String, to: String)?) -> SidebarItem {
        guard case .folder(let raw) = item else { return item }
        let path = FolderPath.normalize(raw)
        if paths.contains(path) { return item }
        if let renamed, FolderPath.contains(renamed.from, path) {
            let moved = renamed.to + path.dropFirst(renamed.from.count)
            if paths.contains(moved) { return .folder(moved) }
        }
        return .all
    }
}
