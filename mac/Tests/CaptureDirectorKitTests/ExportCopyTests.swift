import Foundation
import Testing
@testable import CaptureDirectorKit

@Test func copySummaryComparesSizes() {
    #expect(ExportCopy.summary(preset: "web", size: 3_100_000, original: 42_000_000) == "Web copy \u{00B7} 3.1 MB (was 42.0 MB)")
    #expect(ExportCopy.summary(preset: "small", size: 900_000, original: nil) == "Small copy \u{00B7} 900.0 KB")
}

@Test func copyWordsAndPaths() {
    #expect(ExportCopy.working("web") == "Making web copy\u{2026}")
    #expect(ExportCopy.working("small") == "Making small copy\u{2026}")
    let url = ExportCopy.file(home: URL(fileURLWithPath: "/tmp/h"), id: "abc", preset: "web")
    #expect(url.path == "/tmp/h/exports/abc-web.mp4")
}

@Test func exportOutputDecodes() {
    let json = #"{"id":"a1","preset":"small","file":"/tmp/h/exports/a1-small.mp4","size":1234,"reused":true}"#
    let r = ExportCopy.decode(Data(json.utf8))
    #expect(r == ExportResult(id: "a1", preset: "small", file: "/tmp/h/exports/a1-small.mp4", size: 1234, reused: true))
    #expect(ExportCopy.decode(Data("nope".utf8)) == nil)
}

@Test func copySummaryAdmitsWhenNotSmaller() {
    #expect(ExportCopy.summary(preset: "web", size: 120_000, original: 99_300)
            == "Web copy \u{00B7} 120.0 KB (no smaller than the original, 99.3 KB)")
}

@Test func shownJobPrefersInProgressThenNewest() {
    let t = Date(timeIntervalSince1970: 100)
    let r = ExportResult(id: "a", preset: "web", file: "/x", size: 1, reused: false)
    let done = ExportJob(preset: "web", result: r, at: t)
    let newer = ExportJob(preset: "small", result: r, at: t + 5)
    #expect(ExportJob.shown([done, newer])?.preset == "small")
    #expect(ExportJob.shown([done, ExportJob(preset: "small", at: t - 1)])?.making == true)
    #expect(ExportJob.shown([]) == nil)
}
