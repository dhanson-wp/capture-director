import Foundation

/// easeInOutCubic, the same curve as `ease` in src/util.js, so the real mouse
/// moves and the post-production cursor agree. Input is clamped to 0...1.
public func ease(_ p: Double) -> Double {
    let p = min(1, max(0, p))
    return p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
}

/// What the recorder saw, in the shape `processShot` reads from capture.json.
/// Times are seconds since the capture started; points are in 1920x1080 frame space.
public struct CaptureLog: Sendable {
    public struct Box: Codable, Sendable, Equatable {
        public var x: Double, y: Double, w: Double, h: Double
        public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    }

    struct Event: Codable {
        var type: String
        var t: Double
        var x: Double
        var y: Double
        var zoom: Zoom?
        var focus: Box?
    }

    struct Move: Codable { var t0, t1, x0, y0, x1, y1: Double }
    struct Press: Codable { var t0, t1: Double }

    /// How long the cursor stays down after the button comes up, as in the web recorder.
    static let pressTail = 0.06

    public var cursorStart: [Double]
    var events: [Event] = []
    var moves: [Move] = []
    var presses: [Press] = []

    public init(cursorStart: [Double]) {
        self.cursorStart = cursorStart
    }

    /// A click at `t`, with the button released at `released`.
    public mutating func click(t: Double, released: Double, x: Double, y: Double, zoom: Zoom? = nil, focus: Box? = nil) {
        events.append(Event(type: "click", t: t, x: x, y: y, zoom: zoom, focus: focus))
        presses.append(Press(t0: t, t1: released + Self.pressTail))
    }

    public mutating func hover(t: Double, x: Double, y: Double, zoom: Zoom? = nil, focus: Box? = nil) {
        events.append(Event(type: "hover", t: t, x: x, y: y, zoom: zoom, focus: focus))
    }

    public mutating func move(t0: Double, t1: Double, from: (x: Double, y: Double), to: (x: Double, y: Double)) {
        moves.append(Move(t0: t0, t1: t1, x0: from.x, y0: from.y, x1: to.x, y1: to.y))
    }

    /// A button press that isn't a click (the cursor shows it pressed from `t` to `released` plus a beat).
    public mutating func press(t: Double, released: Double) {
        presses.append(Press(t0: t, t1: released + Self.pressTail))
    }

    private struct File: Encodable {
        struct Viewport: Encodable { var width = 1920, height = 1080 }
        var kind = "app"
        var viewport = Viewport()
        var duration: Double
        var source: String
        var cursorStart: [Double]
        var events: [Event]
        var moves: [Move]
        var presses: [Press]
    }

    public func json(duration: Double, source: String) throws -> Data {
        let file = File(duration: duration, source: source, cursorStart: cursorStart,
                        events: events, moves: moves, presses: presses)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }
}
