import Foundation

public enum SidebarItem: Hashable, Sendable {
    case all, recent, starred, finals, clips, unsorted, folder(String)
}

public enum SortOrder: String, CaseIterable, Sendable {
    case newest, oldest, name, longest
}

public enum Browse {
    public static func apply(_ entries: [LibraryEntry], item: SidebarItem, search: String,
                             sort: SortOrder, now: Date) -> [LibraryEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = entries.filter { matches($0, item, now) && (query.isEmpty || matchesSearch($0, query)) }
        return sorted(matched, sort)
    }

    public static func count(_ entries: [LibraryEntry], item: SidebarItem, now: Date) -> Int {
        entries.filter { matches($0, item, now) }.count
    }

    /// The ids of captures whose video file is gone. `exists` takes the entry's file path.
    public static func missing(_ entries: [LibraryEntry], exists: (String) -> Bool) -> Set<String> {
        Set(entries.filter { !exists($0.file) }.map(\.id))
    }

    private static func matches(_ e: LibraryEntry, _ item: SidebarItem, _ now: Date) -> Bool {
        switch item {
        case .all: return true
        case .recent:
            guard let d = e.updated ?? e.added else { return false }
            return d >= now.addingTimeInterval(-7 * 86_400)
        case .starred: return e.starred
        case .finals: return e.isFinal
        case .clips: return e.kind == "clip"
        case .unsorted: return e.folder.isEmpty
        case .folder(let p): return FolderPath.contains(FolderPath.normalize(p), e.folder)
        }
    }

    private static func matchesSearch(_ e: LibraryEntry, _ q: String) -> Bool {
        [e.title, e.project, e.notes, e.url, e.file].contains {
            $0?.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private static func sorted(_ es: [LibraryEntry], _ order: SortOrder) -> [LibraryEntry] {
        // Offsets keep ties in library order.
        let indexed = Array(es.enumerated())
        func date(_ e: LibraryEntry) -> Date? { e.updated ?? e.added }
        func optional<T>(_ a: T?, _ b: T?, _ before: (T, T) -> Bool) -> Bool? {
            switch (a, b) {
            case let (x?, y?): return before(x, y) ? true : (before(y, x) ? false : nil)
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return nil
            }
        }
        return indexed.sorted { l, r in
            let result: Bool?
            switch order {
            case .newest: result = optional(date(l.element), date(r.element)) { $0 > $1 }
            case .oldest: result = optional(date(l.element), date(r.element)) { $0 < $1 }
            case .longest: result = optional(l.element.duration, r.element.duration) { $0 > $1 }
            case .name:
                let c = l.element.title.localizedStandardCompare(r.element.title)
                result = c == .orderedSame ? nil : c == .orderedAscending
            }
            return result ?? (l.offset < r.offset)
        }.map(\.element)
    }
}
