import Foundation

/// One clip in library.json, as src/library.js writes it. Fields added later
/// (url, size, folders, renames) decode as absent when the file lacks them.
public struct LibraryEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var file: String
    public var title: String
    public var project: String?
    public var kind: String
    public var starred: Bool
    public var notes: String
    public var added: Date?
    public var updated: Date?
    public var source: String?
    public var shot: String?
    public var url: String?
    public var duration: Double?
    public var width: Int?
    public var height: Int?
    public var hasAudio: Bool?
    public var size: Int?

    public var fileURL: URL { URL(fileURLWithPath: file) }
    public var isFinal: Bool { kind == "video" }
    /// Library folder path; "" means Unsorted.
    public var folder: String {
        let trimmed = (project ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "Unsorted" ? "" : trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case id, file, title, project, kind, starred, notes, added, updated
        case source, shot, url, duration, width, height, hasAudio, size
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        file = try c.decode(String.self, forKey: .file)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        project = try? c.decodeIfPresent(String.self, forKey: .project)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "video"
        starred = try c.decodeIfPresent(Bool.self, forKey: .starred) ?? false
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        added = Self.lenientDate(c, .added)
        updated = Self.lenientDate(c, .updated)
        source = try? c.decodeIfPresent(String.self, forKey: .source)
        shot = try? c.decodeIfPresent(String.self, forKey: .shot)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        duration = try? c.decodeIfPresent(Double.self, forKey: .duration)
        width = try? c.decodeIfPresent(Int.self, forKey: .width)
        height = try? c.decodeIfPresent(Int.self, forKey: .height)
        hasAudio = try? c.decodeIfPresent(Bool.self, forKey: .hasAudio)
        size = try? c.decodeIfPresent(Int.self, forKey: .size)
    }

    /// A date that doesn't parse is nil; it never drops the entry.
    private static func lenientDate(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Date? {
        guard let s = try? c.decodeIfPresent(String.self, forKey: key) else { return nil }
        return parseDate(s)
    }

    static func parseDate(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}

public struct Library: Sendable, Equatable {
    public var entries: [LibraryEntry]
    public var folders: [String]
    public var renames: [String: String]

    public init(entries: [LibraryEntry] = [], folders: [String] = [], renames: [String: String] = [:]) {
        self.entries = entries
        self.folders = folders
        self.renames = renames
    }
}

public enum LibraryReader {
    /// `<cdHome>/library.json`, or `~/.capture-director/library.json`.
    public static func file(cdHome: String?) -> URL {
        let home = cdHome.flatMap { $0.isEmpty ? nil : $0 }
            ?? (NSHomeDirectory() + "/.capture-director")
        return URL(fileURLWithPath: home).appendingPathComponent("library.json")
    }

    /// A missing file is an empty library. An entry that can't decode is skipped.
    public static func load(from url: URL) throws -> Library {
        guard FileManager.default.fileExists(atPath: url.path) else { return Library() }
        let data = try Data(contentsOf: url)
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        return Library(entries: raw.entries.compactMap(\.entry), folders: raw.folders ?? [], renames: raw.renames ?? [:])
    }

    private struct Raw: Decodable {
        var entries: [Lossy]
        var folders: [String]?
        var renames: [String: String]?
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            entries = try c.decodeIfPresent([Lossy].self, forKey: .entries) ?? []
            folders = try? c.decodeIfPresent([String].self, forKey: .folders)
            renames = try? c.decodeIfPresent([String: String].self, forKey: .renames)
        }
        enum Keys: String, CodingKey { case entries, folders, renames }
    }

    private struct Lossy: Decodable {
        var entry: LibraryEntry?
        init(from decoder: Decoder) throws { entry = try? LibraryEntry(from: decoder) }
    }
}
