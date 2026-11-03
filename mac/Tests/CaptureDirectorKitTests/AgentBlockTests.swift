import Foundation
import Testing
@testable import CaptureDirectorKit

private func full(kind: String = "clip") -> LibraryEntry {
    let json = """
    {"id":"0123456789abcdef","file":"/Users/me/out/pricing/pricing.mp4","title":"Pricing page tour",
     "kind":"\(kind)","starred":false,"notes":"","url":"https://example.com/pricing",
     "source":"/Users/me/videos/pricing/shots.yaml","shot":"pricing","duration":12,
     "width":1920,"height":1080,"size":4200000}
    """
    return try! JSONDecoder().decode(LibraryEntry.self, from: Data(json.utf8))
}

@Test func agentBlockForOneClip() {
    #expect(AgentBlock.text(for: [full()]) == """
    Capture: Pricing page tour
    File: /Users/me/out/pricing/pricing.mp4
    Length: 0:12 · 1920x1080 · 4.2 MB
    Source site: https://example.com/pricing
    Shot list: /Users/me/videos/pricing/shots.yaml (shot "pricing")
    Click and zoom data: /Users/me/out/pricing/capture.json and zoom-plan.json
    """)
}

@Test func agentBlockLeavesOutMissingDataAndClickDataForFinals() {
    #expect(AgentBlock.text(for: [full(kind: "video")]) == """
    Capture: Pricing page tour
    File: /Users/me/out/pricing/pricing.mp4
    Length: 0:12 · 1920x1080 · 4.2 MB
    Source site: https://example.com/pricing
    Shot list: /Users/me/videos/pricing/shots.yaml (shot "pricing")
    """)
    let bare = try! JSONDecoder().decode(LibraryEntry.self, from: Data(
        #"{"id":"0123456789abcdef","file":"/o/a.mp4","title":"A","kind":"video"}"#.utf8))
    #expect(AgentBlock.text(for: [bare]) == "Capture: A\nFile: /o/a.mp4")
}

@Test func agentBlockJoinsSeveralWithBlankLine() {
    let bare = try! JSONDecoder().decode(LibraryEntry.self, from: Data(
        #"{"id":"0123456789abcdef","file":"/o/a.mp4","title":"A","kind":"video"}"#.utf8))
    #expect(AgentBlock.text(for: [bare, bare]) == "Capture: A\nFile: /o/a.mp4\n\nCapture: A\nFile: /o/a.mp4")
    #expect(AgentBlock.text(for: []) == "")
}
