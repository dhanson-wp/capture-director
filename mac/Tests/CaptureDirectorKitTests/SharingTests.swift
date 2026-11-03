import Foundation
import Testing
@testable import CaptureDirectorKit

private func entry(_ id: String, kind: String = "clip", source: String? = nil, shot: String? = nil,
                   starred: Bool = false) -> LibraryEntry {
    var fields: [String: Any] = ["id": id, "file": "/v/\(id).mp4", "kind": kind, "starred": starred]
    if let source { fields["source"] = source }
    if let shot { fields["shot"] = shot }
    let data = try! JSONSerialization.data(withJSONObject: fields)
    return try! JSONDecoder().decode(LibraryEntry.self, from: data)
}

@Test func shellQuoteLeavesPlainWordsAndPathsAlone() {
    #expect(Shell.quote("pricing") == "pricing")
    #expect(Shell.quote("/Users/me/videos/shots.yaml") == "/Users/me/videos/shots.yaml")
    #expect(Shell.quote("hero-2_a.b") == "hero-2_a.b")
}

@Test func shellQuoteWrapsSpacesQuotesAndSymbols() {
    #expect(Shell.quote("/Users/me/My Videos/shots.yaml") == "'/Users/me/My Videos/shots.yaml'")
    #expect(Shell.quote("Derek's shots.yaml") == "'Derek'\\''s shots.yaml'")
    #expect(Shell.quote("a$b") == "'a$b'")
    #expect(Shell.quote("") == "''")
}

@Test func recordAgainNeedsASourceAndAShot() {
    #expect(entry("a", source: "/s/shots.yaml", shot: "hero").recordAgainCommand
        == "capture-director record /s/shots.yaml --only hero")
    #expect(entry("a", source: "/My Shots/shots.yaml", shot: "hero one").recordAgainCommand
        == "capture-director record '/My Shots/shots.yaml' --only 'hero one'")
    #expect(entry("a", source: "/s/shots.yaml").recordAgainCommand == nil)
    #expect(entry("a", shot: "hero").recordAgainCommand == nil)
    #expect(entry("a", source: "", shot: "hero").recordAgainCommand == nil)
    #expect(entry("a", source: "/s/shots.yaml", shot: "").recordAgainCommand == nil)
}

@Test func dragCarriesTheSelectionWhenTheDraggedItemIsInIt() {
    let order = ["a", "b", "c", "d"].map { entry($0) }
    // In screen order, whatever order the set gives.
    #expect(DragSet.entries(dragging: order[2], selection: ["d", "b", "c"], in: order).map(\.id) == ["b", "c", "d"])
    #expect(DragSet.entries(dragging: order[0], selection: ["a"], in: order).map(\.id) == ["a"])
}

@Test func dragCarriesOnlyTheDraggedItemWhenItIsNotSelected() {
    let order = ["a", "b", "c"].map { entry($0) }
    #expect(DragSet.entries(dragging: order[0], selection: ["b", "c"], in: order).map(\.id) == ["a"])
    #expect(DragSet.entries(dragging: order[1], selection: [], in: order).map(\.id) == ["b"])
}

@Test func bulkStarStarsUnlessEveryOneIsStarred() {
    #expect(Bulk.starTarget([entry("a", starred: true), entry("b")]) == true)
    #expect(Bulk.starTarget([entry("a", starred: true), entry("b", starred: true)]) == false)
    #expect(Bulk.starTarget([]) == true)
}
