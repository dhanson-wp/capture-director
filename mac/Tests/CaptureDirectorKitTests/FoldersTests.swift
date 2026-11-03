import Foundation
import Testing
@testable import CaptureDirectorKit

func makeEntry(_ id: String = "0123456789abcdef", title: String = "T", project: String? = nil,
               kind: String = "video", starred: Bool = false, notes: String = "",
               added: Date? = nil, updated: Date? = nil, file: String = "/x/a.mp4",
               duration: Double? = nil, url: String? = nil) -> LibraryEntry {
    var json: [String: Any] = ["id": id, "file": file, "title": title, "kind": kind,
                               "starred": starred, "notes": notes]
    if let project { json["project"] = project }
    if let duration { json["duration"] = duration }
    if let url { json["url"] = url }
    let data = try! JSONSerialization.data(withJSONObject: json)
    var e = try! JSONDecoder().decode(LibraryEntry.self, from: data)
    e.added = added
    e.updated = updated
    return e
}

@Test func folderPathsNormalizeLikeNode() {
    #expect(FolderPath.normalize(" a / /b ") == "a/b")
    #expect(FolderPath.normalize("a/") == "a")
    #expect(FolderPath.normalize("🎬 Demos") == "🎬 Demos")
    #expect(FolderPath.normalize("  a / b  ") == "a/b")
    #expect(FolderPath.normalize("a//b/") == "a/b")
    #expect(FolderPath.normalize("/") == "")
    #expect(FolderPath.normalize("Unsorted") == "")
    #expect(FolderPath.normalize(" Unsorted\t") == "")
    #expect(FolderPath.normalize("Unsorted/x") == "Unsorted/x")
    #expect(FolderPath.name("blog/Post formats") == "Post formats")
    #expect(FolderPath.name("blog") == "blog")
    #expect(FolderPath.contains("blog", "blog"))
    #expect(FolderPath.contains("blog", "blog/x"))
    #expect(!FolderPath.contains("blog", "blogs"))
}

@Test func treeIncludesEmptyAndAncestorFolders() {
    let lib = Library(entries: [makeEntry("a", project: "blog/Post formats"), makeEntry("b", project: "Unsorted")],
                      folders: ["Empty"])
    let tree = FolderTree.build(lib)
    #expect(tree.map(\.path) == ["blog", "Empty"])
    #expect(tree[0].count == 1)
    #expect(tree[0].children.map(\.path) == ["blog/Post formats"])
    #expect(tree[0].children[0].name == "Post formats")
    #expect(tree[0].children[0].count == 1)
    #expect(tree[1].count == 0)
    let parents = FolderTree.build(Library(folders: ["a/b"]))
    #expect(parents.map(\.path) == ["a"])
    #expect(parents[0].children.map(\.path) == ["a/b"])
}

@Test func sizeFormatIsStable() {
    #expect(Format.size(4_200_000) == "4.2 MB")
    #expect(Format.size(999) == "999 B")
    #expect(Format.size(1_500) == "1.5 KB")
}
