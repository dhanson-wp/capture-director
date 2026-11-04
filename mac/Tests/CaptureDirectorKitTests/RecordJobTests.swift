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

@Test func unknownStepAndTargetlessClickSayWhy() {
    func message(_ steps: String) -> String {
        do { _ = try load(jobJSON(steps: steps)); return "" } catch { return error.localizedDescription }
    }
    #expect(message(#"[{"kind":"drag","by":[1,2]}]"#).contains("\"drag\""))
    #expect(message(#"[{"kind":"click"}]"#).contains("needs an id, a label, or a target"))
}
