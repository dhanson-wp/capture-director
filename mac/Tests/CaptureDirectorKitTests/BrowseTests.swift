import Foundation
import Testing
@testable import CaptureDirectorKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

@Test func recentIsSevenDays() {
    let es = [makeEntry("a", added: ago(6)), makeEntry("b", added: ago(8)),
              makeEntry("c", added: ago(30), updated: ago(1)), makeEntry("d")]
    let r = Browse.apply(es, item: .recent, search: "", sort: .newest, now: now)
    #expect(r.map(\.id) == ["c", "a"])
    #expect(Browse.count(es, item: .recent, now: now) == 2)
}

@Test func folderIncludesDescendants() {
    let es = [makeEntry("a", project: "blog"), makeEntry("b", project: "blog/x"),
              makeEntry("c", project: "blogs"), makeEntry("d")]
    #expect(Browse.apply(es, item: .folder("blog"), search: "", sort: .name, now: now).map(\.id) == ["a", "b"])
    #expect(Browse.apply(es, item: .unsorted, search: "", sort: .name, now: now).map(\.id) == ["d"])
    #expect(Browse.count(es, item: .all, now: now) == 4)
}

@Test func finalsAndClips() {
    let es = [makeEntry("a", kind: "video"), makeEntry("b", kind: "clip"), makeEntry("c", starred: true)]
    #expect(Browse.apply(es, item: .finals, search: "", sort: .name, now: now).map(\.id) == ["a", "c"])
    #expect(Browse.apply(es, item: .clips, search: "", sort: .name, now: now).map(\.id) == ["b"])
    #expect(Browse.apply(es, item: .starred, search: "", sort: .name, now: now).map(\.id) == ["c"])
}

@Test func searchMatchesTitleProjectNotesURLAndFile() {
    let es = [makeEntry("a", title: "Pricing"), makeEntry("b", project: "Launch"),
              makeEntry("c", notes: "hero shot"), makeEntry("d", url: "https://Example.com/x"),
              makeEntry("e", file: "/out/Tour.mp4")]
    func ids(_ s: String) -> [String] { Browse.apply(es, item: .all, search: s, sort: .name, now: now).map(\.id) }
    #expect(ids("PRICING") == ["a"])
    #expect(ids("launch") == ["b"])
    #expect(ids("HERO") == ["c"])
    #expect(ids("example.com") == ["d"])
    #expect(ids("tour") == ["e"])
    #expect(ids("  ").count == 5)
}

@Test func sortOrders() {
    let es = [makeEntry("a", title: "File 10", added: ago(5), duration: 5),
              makeEntry("b", title: "File 2", updated: ago(1), duration: 30),
              makeEntry("c", title: "file 1"),
              makeEntry("d", title: "Zed", added: ago(9), duration: 10)]
    func ids(_ s: CaptureDirectorKit.SortOrder) -> [String] { Browse.apply(es, item: .all, search: "", sort: s, now: now).map(\.id) }
    #expect(ids(.newest) == ["b", "a", "d", "c"])
    #expect(ids(.oldest) == ["d", "a", "b", "c"])
    #expect(ids(.name) == ["c", "b", "a", "d"])
    #expect(ids(.longest) == ["b", "d", "a", "c"])
}
