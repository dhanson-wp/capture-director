import Foundation

/// What the Node side hands the Mac recorder: one app shot, ready to play.
/// Steps arrive as `normalizeStep` output (`{ kind, ... }`).
public struct RecordJob: Codable, Sendable {
    public struct AppRef: Codable, Sendable, Equatable {
        public var bundleId: String?
        public var path: String?

        public init(bundleId: String? = nil, path: String? = nil) {
            self.bundleId = bundleId
            self.path = path
        }
    }

    public struct Size: Codable, Sendable, Equatable {
        public var width: Double
        public var height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    public var version: Int
    public var id: String
    public var app: AppRef
    public var env: [String: String]
    public var window: Size
    public var background: String
    public var fps: Int
    public var countdown: Double
    public var settle: Int
    public var tail: Int
    public var cursorStart: [Double]?
    public var steps: [Step]
    public var out: String

    enum CodingKeys: String, CodingKey {
        case version, id, app, env, window, background, fps, countdown, settle, tail, cursorStart, steps, out
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        id = try c.decode(String.self, forKey: .id)
        app = try c.decode(AppRef.self, forKey: .app)
        env = try c.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        window = try c.decode(Size.self, forKey: .window)
        background = try c.decode(String.self, forKey: .background)
        fps = try c.wholeNumber(.fps)
        countdown = try c.decode(Double.self, forKey: .countdown)
        settle = try c.wholeNumber(.settle)
        tail = try c.wholeNumber(.tail)
        cursorStart = try c.decodeIfPresent([Double].self, forKey: .cursorStart)
        steps = try c.decode([Step].self, forKey: .steps)
        out = try c.decode(String.self, forKey: .out)
    }

    /// Reads and checks a job file. Node checks the same rules first; this is defense in depth.
    public static func load(from url: URL) throws -> RecordJob {
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            throw RecordJobError("I couldn't read the job file at \(url.lastPathComponent).")
        }
        let job: RecordJob
        do { job = try JSONDecoder().decode(RecordJob.self, from: data) } catch let error as DecodingError {
            throw RecordJobError("The job file isn't valid: \(describe(error))")
        }
        try job.validate()
        return job
    }

    public func validate() throws {
        guard version == 1 else { throw RecordJobError("This job file is version \(version); I only know version 1.") }
        guard !id.isEmpty else { throw RecordJobError("The job needs an id.") }
        guard app.bundleId?.isEmpty == false || app.path?.isEmpty == false else {
            throw RecordJobError("The job needs an app bundle ID or path.")
        }
        guard background.range(of: #"^#[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil else {
            throw RecordJobError("The background must be a hex color like #4c1637.")
        }
        guard window.width.isFinite, window.height.isFinite,
              (760...3000).contains(window.width), (480...2000).contains(window.height) else {
            throw RecordJobError("The window size must be between 760x480 and 3000x2000.")
        }
        for key in env.keys.sorted() {
            guard key.range(of: #"^[A-Z_][A-Z0-9_]*$"#, options: .regularExpression) != nil else {
                throw RecordJobError("\"\(key)\" isn't a valid environment variable name.")
            }
            // Dynamic-loader variables would load code into the target app.
            guard !key.hasPrefix("DYLD_"), !key.hasPrefix("LD_") else {
                throw RecordJobError("env can't set \(key); loader variables aren't allowed.")
            }
        }
        guard fps > 0 else { throw RecordJobError("The frame rate must be above zero.") }
        guard countdown.isFinite, countdown >= 0, settle >= 0, tail >= 0 else {
            throw RecordJobError("The countdown, settle, and tail times can't be negative.")
        }
        if let start = cursorStart {
            guard start.count == 2, start.allSatisfy(\.isFinite) else {
                throw RecordJobError("The cursor start must be two numbers.")
            }
        }
        guard !steps.isEmpty else { throw RecordJobError("The job has no steps.") }
        for case .scroll(let by, _) in steps {
            guard by.isFinite, abs(by) <= 1e6 else {
                throw RecordJobError("scroll by must be between -1000000 and 1000000.")
            }
        }
        guard !out.isEmpty else { throw RecordJobError("The job needs an output folder.") }
    }

    private static func describe(_ error: DecodingError) -> String {
        func path(_ ctx: DecodingError.Context) -> String {
            let parts = ctx.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
            return parts.isEmpty ? "" : "\"" + parts.joined(separator: ".") + "\": "
        }
        switch error {
        case .dataCorrupted(let ctx), .typeMismatch(_, let ctx), .valueNotFound(_, let ctx):
            return path(ctx) + ctx.debugDescription
        case .keyNotFound(let key, let ctx):
            return path(ctx) + "\"\(key.stringValue)\" is missing."
        @unknown default:
            return "it couldn't be read."
        }
    }
}

extension KeyedDecodingContainer {
    /// Node passes numbers through unrounded (`ms: 1500.5`), so read a Double and round.
    /// Rejects values that are negative or too big to be a time or rate.
    func wholeNumber(_ key: Key) throws -> Int {
        let value = try decode(Double.self, forKey: key)
        guard value.isFinite, value >= 0, value < 1e9 else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "\(key.stringValue) must be a number from 0 up, not \(value).")
        }
        return Int(value.rounded())
    }

    func wholeNumberIfPresent(_ key: Key) throws -> Int? {
        contains(key) && (try? decodeNil(forKey: key)) != true ? try wholeNumber(key) : nil
    }
}

public struct RecordJobError: Error, LocalizedError, Equatable {
    public let message: String
    init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Which element a click or hover aims at: an accessibility id, or a label (optionally with a role).
public enum Target: Codable, Sendable, Equatable {
    case id(String)
    case roleLabel(role: String?, label: String)

    enum CodingKeys: String, CodingKey { case id, role, label, target }

    /// Reads the target out of a step's top level: `id`, or `role` + `label`, or `target` (a bare label).
    /// Returns nil when the step names no target at all.
    static func read(from c: KeyedDecodingContainer<CodingKeys>) throws -> Target? {
        if let id = try c.decodeIfPresent(String.self, forKey: .id) { return .id(id) }
        let role = try c.decodeIfPresent(String.self, forKey: .role)
        if let label = try c.decodeIfPresent(String.self, forKey: .label) { return .roleLabel(role: role, label: label) }
        if let label = try? c.decodeIfPresent(String.self, forKey: .target) { return .roleLabel(role: role, label: label) }
        return nil
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let target = try Target.read(from: c) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "A target needs an id, a label, or a target.")
        }
        self = target
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .id(let id): try c.encode(id, forKey: .id)
        case .roleLabel(let role, let label):
            try c.encodeIfPresent(role, forKey: .role)
            try c.encode(label, forKey: .label)
        }
    }
}

/// Where a `move` goes: a point in 1920x1080 frame space, or an element.
public enum MoveTo: Sendable, Equatable {
    case point(x: Double, y: Double)
    case target(Target)
}

/// A step's own zoom (Ruling M): a level, or `false` for no zoom on that event.
/// capture.json carries it the same way, so `processShot` skips `false` events.
public enum Zoom: Codable, Sendable, Equatable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    case level(Double)
    case off

    public init(floatLiteral value: Double) { self = .level(value) }
    public init(integerLiteral value: Int) { self = .level(Double(value)) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let on = try? c.decode(Bool.self) {
            guard !on else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "zoom must be a number or false.")
            }
            self = .off
            return
        }
        let value = try c.decode(Double.self)
        guard value.isFinite else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "zoom must be a number or false.")
        }
        self = .level(value)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .level(let value): try c.encode(value)
        case .off: try c.encode(false)
        }
    }
}

public enum Step: Codable, Sendable, Equatable {
    case wait(ms: Int)
    case click(Target, zoom: Zoom?, hold: Int?, duration: Int?)
    case hover(Target, zoom: Zoom?, hold: Int?, duration: Int?)
    case move(to: MoveTo, duration: Int?)
    case press(key: String)
    case type(text: String)
    case scroll(by: Double, duration: Int?)

    enum CodingKeys: String, CodingKey { case kind, ms, zoom, hold, duration, point, key, text, by, id, role, label, target }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        let targetKeys = try decoder.container(keyedBy: Target.CodingKeys.self)

        func needTarget() throws -> Target {
            guard let t = try Target.read(from: targetKeys) else {
                throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "A \(kind) step needs an id, a label, or a target.")
            }
            return t
        }

        // `zoom: true` is the shot's own zoom, the same as leaving it out.
        func zoom() throws -> Zoom? {
            if (try? c.decode(Bool.self, forKey: .zoom)) == true { return nil }
            return try c.decodeIfPresent(Zoom.self, forKey: .zoom)
        }

        switch kind {
        case "wait":
            self = .wait(ms: try c.wholeNumber(.ms))
        case "click":
            self = .click(try needTarget(), zoom: try zoom(),
                          hold: try c.wholeNumberIfPresent(.hold),
                          duration: try c.wholeNumberIfPresent(.duration))
        case "hover":
            self = .hover(try needTarget(), zoom: try zoom(),
                          hold: try c.wholeNumberIfPresent(.hold),
                          duration: try c.wholeNumberIfPresent(.duration))
        case "move":
            let duration = try c.wholeNumberIfPresent(.duration)
            if let p = try c.decodeIfPresent([Double].self, forKey: .point) {
                guard p.count == 2, p.allSatisfy(\.isFinite) else {
                    throw DecodingError.dataCorruptedError(forKey: .point, in: c, debugDescription: "A move point needs two numbers.")
                }
                self = .move(to: .point(x: p[0], y: p[1]), duration: duration)
            } else {
                self = .move(to: .target(try needTarget()), duration: duration)
            }
        case "press":
            self = .press(key: try c.decode(String.self, forKey: .key))
        case "type":
            self = .type(text: try c.decode(String.self, forKey: .text))
        case "scroll":
            self = .scroll(by: try c.decode(Double.self, forKey: .by), duration: try c.wholeNumberIfPresent(.duration))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Mac app shots don't support the \"\(kind)\" step.")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        func target(_ t: Target) throws {
            switch t {
            case .id(let id): try c.encode(id, forKey: .id)
            case .roleLabel(let role, let label):
                try c.encodeIfPresent(role, forKey: .role)
                try c.encode(label, forKey: .label)
            }
        }
        switch self {
        case .wait(let ms):
            try c.encode("wait", forKey: .kind); try c.encode(ms, forKey: .ms)
        case .click(let t, let zoom, let hold, let duration), .hover(let t, let zoom, let hold, let duration):
            if case .click = self { try c.encode("click", forKey: .kind) } else { try c.encode("hover", forKey: .kind) }
            try target(t)
            try c.encodeIfPresent(zoom, forKey: .zoom)
            try c.encodeIfPresent(hold, forKey: .hold)
            try c.encodeIfPresent(duration, forKey: .duration)
        case .move(let to, let duration):
            try c.encode("move", forKey: .kind)
            switch to {
            case .point(let x, let y): try c.encode([x, y], forKey: .point)
            case .target(let t): try target(t)
            }
            try c.encodeIfPresent(duration, forKey: .duration)
        case .press(let key):
            try c.encode("press", forKey: .kind); try c.encode(key, forKey: .key)
        case .type(let text):
            try c.encode("type", forKey: .kind); try c.encode(text, forKey: .text)
        case .scroll(let by, let duration):
            try c.encode("scroll", forKey: .kind); try c.encode(by, forKey: .by)
            try c.encodeIfPresent(duration, forKey: .duration)
        }
    }
}
