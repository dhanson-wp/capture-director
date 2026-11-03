import Foundation

/// Folder paths as src/library.js `normalizeFolder` writes them, minus the length check.
public enum FolderPath {
    private static let jsSpace = CharacterSet.whitespacesAndNewlines

    public static func normalize(_ p: String) -> String {
        let out = p.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: jsSpace) }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        return out == "Unsorted" ? "" : out
    }

    /// The last level of a path.
    public static func name(_ p: String) -> String {
        p.split(separator: "/").last.map(String.init) ?? p
    }

    /// True when `child` is `parent` or sits below it.
    public static func contains(_ parent: String, _ child: String) -> Bool {
        child == parent || child.hasPrefix(parent + "/")
    }
}

public struct FolderNode: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public var path: String
    public var name: String
    /// Entries in this folder and every folder below it.
    public var count: Int
    public var children: [FolderNode]
}

public enum FolderTree {
    /// Folders from entries and the explicit list, plus every parent, sorted by name.
    public static func build(_ library: Library) -> [FolderNode] {
        var paths = Set<String>()
        func add(_ raw: String) {
            let p = FolderPath.normalize(raw)
            guard !p.isEmpty else { return }
            var prefix: [Substring] = []
            for part in p.split(separator: "/") {
                prefix.append(part)
                paths.insert(prefix.joined(separator: "/"))
            }
        }
        library.entries.forEach { add($0.folder) }
        library.folders.forEach(add)
        let folders = library.entries.map(\.folder)

        func nodes(under parent: String?) -> [FolderNode] {
            paths.filter { p in
                let up = p.split(separator: "/").dropLast().joined(separator: "/")
                return parent == nil ? up.isEmpty : up == parent
            }
            .map { p in
                FolderNode(path: p, name: FolderPath.name(p),
                           count: folders.filter { FolderPath.contains(p, $0) }.count,
                           children: nodes(under: p))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return nodes(under: nil)
    }

    /// Every folder path, parents before children, in sidebar order. The project pickers list these.
    public static func paths(_ library: Library) -> [String] {
        func walk(_ nodes: [FolderNode]) -> [String] { nodes.flatMap { [$0.path] + walk($0.children) } }
        return walk(build(library))
    }
}
