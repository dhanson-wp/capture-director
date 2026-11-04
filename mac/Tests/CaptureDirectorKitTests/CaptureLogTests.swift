import Foundation
import Testing
@testable import CaptureDirectorKit

@Test func easeMatchesTheNodeCurve() {
    #expect(ease(0.25) == 0.0625)
    #expect(ease(0.75) == 0.9375)
    #expect(ease(0.5) == 0.5)
    #expect(ease(-1) == 0)
    #expect(ease(2) == 1)
}

@Test func captureLogWritesWhatProcessShotReads() throws {
    var log = CaptureLog(cursorStart: [1190.4, 777.6])
    log.move(t0: 0.5, t1: 1.4, from: (x: 1190.4, y: 777.6), to: (x: 300, y: 200))
    log.click(t: 1.5, released: 1.59, x: 300, y: 200, zoom: 1.7, focus: .init(x: 300, y: 200, w: 80, h: 40))
    log.hover(t: 3, x: 500, y: 400)
    let obj = try #require(JSONSerialization.jsonObject(with: try log.json(duration: 4.2, source: "clip.mov")) as? [String: Any])
    #expect(obj["kind"] as? String == "app")
    #expect(obj["source"] as? String == "clip.mov")
    #expect(obj["duration"] as? Double == 4.2)
    #expect(obj["viewport"] as? [String: Int] == ["width": 1920, "height": 1080])
    #expect(obj["cursorStart"] as? [Double] == [1190.4, 777.6])
    let events = try #require(obj["events"] as? [[String: Any]])
    #expect(events[0]["type"] as? String == "click")
    #expect(events[0]["zoom"] as? Double == 1.7)
    #expect((events[0]["focus"] as? [String: Double])?["w"] == 80)
    #expect(events[1]["type"] as? String == "hover")
    #expect(events[1]["zoom"] == nil)
    let presses = try #require(obj["presses"] as? [[String: Double]])
    #expect(presses.count == 1)
    #expect(presses[0]["t0"] == 1.5)
    #expect(abs(presses[0]["t1"]! - 1.65) < 1e-9)
    let moves = try #require(obj["moves"] as? [[String: Double]])
    #expect(moves[0] == ["t0": 0.5, "t1": 1.4, "x0": 1190.4, "y0": 777.6, "x1": 300, "y1": 200])
}

@Test func captureLogThrowsOnNonFiniteNumbersInsteadOfCrashing() {
    var log = CaptureLog(cursorStart: [0, 0])
    log.hover(t: .nan, x: 1, y: 1)
    #expect(throws: (any Error).self) { try log.json(duration: 1, source: "clip.mov") }
}
