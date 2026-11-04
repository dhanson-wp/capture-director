import Foundation
import Testing
@testable import CaptureDirectorKit

private func jobJSON(version: Int = 1, background: String = "#4c1637", steps: String? = nil, window: String = #"{"width":1440,"height":900}"#, env: String = #"{"HOME_DIR":"/tmp/x"}"#) -> Data {
    let steps = steps ?? """
    [{"kind":"wait","ms":800},
     {"kind":"click","id":"inspector","zoom":1.7,"hold":2400},
     {"kind":"click","role":"row","label":"Starred"},
     {"kind":"hover","target":"Starred"},
     {"kind":"move","point":[960,540],"duration":900},
     {"kind":"move","id":"inspector"},
     {"kind":"press","key":"cmd+o"},
     {"kind":"type","text":"hello"},
     {"kind":"scroll","by":600,"duration":1200}]
    """
    return Data("""
    {"version":\(version),"id":"tour","app":{"bundleId":"io.example.app"},"env":\(env),
     "window":\(window),"background":"\(background)","fps":30,"countdown":3,"settle":400,"tail":600,
     "steps":\(steps),"out":"/tmp/out"}
    """.utf8)
}

private func load(_ data: Data) throws -> RecordJob {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("job-\(UUID().uuidString).json")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    return try RecordJob.load(from: url)
}

@Test func decodesEveryStepKind() throws {
    let job = try load(jobJSON())
    #expect(job.steps == [
        .wait(ms: 800),
        .click(.id("inspector"), zoom: 1.7, hold: 2400, duration: nil),
        .click(.roleLabel(role: "row", label: "Starred"), zoom: nil, hold: nil, duration: nil),
        .hover(.roleLabel(role: nil, label: "Starred"), zoom: nil, hold: nil, duration: nil),
        .move(to: .point(x: 960, y: 540), duration: 900),
        .move(to: .target(.id("inspector")), duration: nil),
        .press(key: "cmd+o"),
        .type(text: "hello"),
        .scroll(by: 600, duration: 1200),
    ])
    #expect(job.app.bundleId == "io.example.app")
    #expect(job.cursorStart == nil)
}

@Test func rejectsBadJobs() {
    #expect(throws: RecordJobError.self) { try load(jobJSON(version: 2)) }
    #expect(throws: RecordJobError.self) { try load(jobJSON(background: "red")) }
    #expect(throws: RecordJobError.self) { try load(jobJSON(steps: "[]")) }
    #expect(throws: RecordJobError.self) { try load(jobJSON(window: #"{"width":700,"height":900}"#)) }
    #expect(throws: RecordJobError.self) { try load(jobJSON(window: #"{"width":1440,"height":2001}"#)) }
    #expect(throws: RecordJobError.self) { try load(jobJSON(env: #"{"bad-name":"x"}"#)) }
}

@Test func envRefusesLoaderVariables() {
    func message(_ env: String) -> String {
        do { _ = try load(jobJSON(env: env)); return "" } catch { return error.localizedDescription }
    }
    #expect(message(#"{"DYLD_INSERT_LIBRARIES":"/tmp/x.dylib"}"#) == "env can't set DYLD_INSERT_LIBRARIES; loader variables aren't allowed.")
    #expect(message(#"{"LD_LIBRARY_PATH":"/tmp"}"#) == "env can't set LD_LIBRARY_PATH; loader variables aren't allowed.")
    #expect(message(#"{"OLD_DYLD":"x"}"#) == "")
}

@Test func stepZoomIsANumberOrFalse() throws {
    let job = try load(jobJSON(steps: #"[{"kind":"click","id":"a","zoom":false},{"kind":"hover","id":"b","zoom":2},{"kind":"click","id":"c","zoom":true},{"kind":"hover","id":"d","zoom":1.5}]"#))
    #expect(job.steps == [
        .click(.id("a"), zoom: .off, hold: nil, duration: nil),
        .hover(.id("b"), zoom: .level(2), hold: nil, duration: nil),
        .click(.id("c"), zoom: nil, hold: nil, duration: nil),
        .hover(.id("d"), zoom: .level(1.5), hold: nil, duration: nil),
    ])
    #expect(throws: RecordJobError.self) { try load(jobJSON(steps: #"[{"kind":"click","id":"a","zoom":"big"}]"#)) }
}

@Test func stepZoomRoundTrips() throws {
    let steps: [Step] = [.click(.id("a"), zoom: .off, hold: nil, duration: nil), .hover(.id("b"), zoom: .level(1.7), hold: nil, duration: nil)]
    let data = try JSONEncoder().encode(steps)
    let raw = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    #expect(raw[0]["zoom"] as? Bool == false)
    #expect(raw[1]["zoom"] as? Double == 1.7)
    #expect(try JSONDecoder().decode([Step].self, from: data) == steps)
}

@Test func unknownStepAndTargetlessClickSayWhy() {
    func message(_ steps: String) -> String {
        do { _ = try load(jobJSON(steps: steps)); return "" } catch { return error.localizedDescription }
    }
    #expect(message(#"[{"kind":"drag","by":[1,2]}]"#).contains("\"drag\""))
    #expect(message(#"[{"kind":"click"}]"#).contains("needs an id, a label, or a target"))
}

@Test func fractionalTimesRoundInsteadOfFailing() throws {
    let job = try load(jobJSON(steps: #"[{"kind":"wait","ms":1500.5},{"kind":"click","id":"a","hold":2400.4,"duration":900.5}]"#))
    #expect(job.steps == [.wait(ms: 1501), .click(.id("a"), zoom: nil, hold: 2400, duration: 901)])
}

@Test func badTimesNameTheField() {
    func message(_ steps: String) -> String {
        do { _ = try load(jobJSON(steps: steps)); return "" } catch { return error.localizedDescription }
    }
    let m = message(#"[{"kind":"wait","ms":-5}]"#)
    #expect(m.contains("ms") && m.contains("steps"))
    #expect(message(#"[{"kind":"click","id":"a","hold":"soon"}]"#).contains("hold"))
}
