import Foundation

/// What `capture-director library export` prints.
public struct ExportResult: Decodable, Equatable, Sendable {
    public let id: String
    public let preset: String
    public let file: String
    public let size: Int
    public let reused: Bool

    public init(id: String, preset: String, file: String, size: Int, reused: Bool) {
        self.id = id
        self.preset = preset
        self.file = file
        self.size = size
        self.reused = reused
    }

    public var url: URL { URL(fileURLWithPath: file) }
}

/// A copy being made or finished, kept by the store so a view torn down and rebuilt still sees it.
public struct ExportJob: Equatable, Sendable {
    public let preset: String
    /// Nil while it's being made.
    public var result: ExportResult?
    public let at: Date

    public init(preset: String, result: ExportResult? = nil, at: Date = .now) {
        self.preset = preset
        self.result = result
        self.at = at
    }

    public var making: Bool { result == nil }

    /// The job to show for one capture: one in progress first, else the newest finished.
    public static func shown(_ jobs: [ExportJob]) -> ExportJob? {
        jobs.first(where: \.making) ?? jobs.max { $0.at < $1.at }
    }
}

/// Web copies: smaller videos for upload pages with size limits. They live in
/// the library home's `exports` folder, never next to the original.
public enum ExportCopy {
    public static let presets = ["web", "small"]

    /// "Web copy" or "Small copy".
    public static func title(_ preset: String) -> String { preset == "small" ? "Small copy" : "Web copy" }

    /// "Making web copy…"
    public static func working(_ preset: String) -> String { "Making \(title(preset).lowercased())\u{2026}" }

    /// "Web copy · 3.1 MB (was 42.0 MB)"; just the copy's size when the original's is unknown.
    public static func summary(preset: String, size: Int, original: Int?) -> String {
        var line = "\(title(preset)) \u{00B7} \(Format.size(size))"
        if let original {
            line += size >= original ? " (no smaller than the original, \(Format.size(original)))"
                                     : " (was \(Format.size(original)))"
        }
        return line
    }

    /// Where the CLI keeps a capture's copy: `<home>/exports/<id>-<preset>.mp4`.
    public static func file(home: URL, id: String, preset: String) -> URL {
        home.appendingPathComponent("exports").appendingPathComponent("\(id)-\(preset).mp4")
    }

    public static func decode(_ data: Data) -> ExportResult? {
        try? JSONDecoder().decode(ExportResult.self, from: data)
    }
}
