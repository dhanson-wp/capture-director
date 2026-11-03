import Foundation
import Testing
@testable import CaptureDirectorKit

@Test func parentOfAPath() {
    #expect(FolderEdit.parent("blog/Post formats") == "blog")
    #expect(FolderEdit.parent("a/b/c") == "a/b")
    #expect(FolderEdit.parent("blog") == "")
    #expect(FolderEdit.parent("") == "")
}

@Test func newFolderNamesCountUpUnderTheParent() {
    #expect(FolderEdit.newFolderPath(under: "", existing: []) == "New folder")
    #expect(FolderEdit.newFolderPath(under: "", existing: ["New folder"]) == "New folder 2")
    #expect(FolderEdit.newFolderPath(under: "", existing: ["New folder", "New folder 2", "New folder 4"]) == "New folder 3")
    // Only the parent's own children count: a "New folder" elsewhere doesn't.
    #expect(FolderEdit.newFolderPath(under: "blog", existing: ["New folder", "blog"]) == "blog/New folder")
    #expect(FolderEdit.newFolderPath(under: "blog", existing: ["blog", "blog/New folder", "blog/New folder/New folder 2"])
        == "blog/New folder 2")
    // A case-only match is taken too, so two near-identical names never sit side by side.
    #expect(FolderEdit.newFolderPath(under: "", existing: ["new folder"]) == "New folder 2")
}

@Test func renameKeepsTheParent() {
    #expect(FolderEdit.renameTarget("blog/Post formats", to: "Formats") == "blog/Formats")
    #expect(FolderEdit.renameTarget("Spacefast", to: "Spacefast launch") == "Spacefast launch")
    #expect(FolderEdit.renameTarget("blog/Old", to: "  New  ") == "blog/New")
    // Nothing to do: empty, or the same name.
    #expect(FolderEdit.renameTarget("blog/Old", to: "   ") == nil)
    #expect(FolderEdit.renameTarget("blog/Old", to: "Old") == nil)
    // A case-only change is a real rename.
    #expect(FolderEdit.renameTarget("blog", to: "Blog") == "Blog")
}

@Test func movingAFolderIntoAnother() {
    #expect(FolderEdit.moveTarget("Spacefast", into: "blog") == "blog/Spacefast")
    #expect(FolderEdit.moveTarget("blog/Post formats", into: "") == "Post formats")
    #expect(FolderEdit.moveTarget("blog/Post formats", into: "Spacefast") == "Spacefast/Post formats")
    // Not into itself, not below itself, not where it already is.
    #expect(FolderEdit.moveTarget("blog", into: "blog") == nil)
    #expect(FolderEdit.moveTarget("blog", into: "blog/Post formats") == nil)
    #expect(FolderEdit.moveTarget("blog/Post formats", into: "blog") == nil)
    #expect(FolderEdit.moveTarget("Spacefast", into: "") == nil)
    // "blogs" isn't inside "blog".
    #expect(FolderEdit.moveTarget("blog", into: "blogs") == "blogs/blog")
}

@Test func droppedFilesMapBackToCaptures() {
    let entries = [makeEntry("a", project: "blog", file: "/v/a.mp4"),
                   makeEntry("b", project: "Unsorted", file: "/v/b b.mp4"),
                   makeEntry("c", project: "Spacefast", file: "/v/c.mp4")]
    let urls = [URL(fileURLWithPath: "/v/b b.mp4"), URL(fileURLWithPath: "/elsewhere/x.mp4"),
                URL(fileURLWithPath: "/v/./a.mp4"), URL(fileURLWithPath: "/v/b b.mp4")]
    // In dropped order, once each, leaving out files that aren't in the library.
    #expect(FolderEdit.entryIDs(dropped: urls, in: entries) == ["b", "a"])
    // Captures already in the folder aren't moved again.
    #expect(FolderEdit.entryIDs(dropped: urls, in: entries, movingTo: "blog") == ["b"])
    #expect(FolderEdit.entryIDs(dropped: urls, in: entries, movingTo: "") == ["a"])
    #expect(FolderEdit.entryIDs(dropped: [URL(string: "https://example.com/a.mp4")!], in: entries).isEmpty)
}

@Test func droppedFilesMatchThroughSymlinks() throws {
    // /tmp is a link to /private/tmp on macOS; Finder hands over either.
    let dir = URL(fileURLWithPath: "/tmp/cd-folderedit-\(getpid())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("a.mp4")
    FileManager.default.createFile(atPath: file.path, contents: Data())
    let entries = [makeEntry("a", file: file.path)]
    let other = URL(fileURLWithPath: "/private" + file.path)
    #expect(FolderEdit.entryIDs(dropped: [other], in: entries) == ["a"])
}

@Test func onlyEmptyFoldersCanBeDeleted() {
    let lib = Library(entries: [makeEntry("a", project: "blog/Post formats")], folders: ["blog", "Empty", "Empty/Inner"])
    let deletable = FolderEdit.deletable(FolderTree.build(lib))
    #expect(deletable == ["Empty", "Empty/Inner"])
    #expect(!deletable.contains("blog"))
    #expect(!deletable.contains("blog/Post formats"))
}

@Test func aVanishedFolderFallsBack() {
    let paths = ["blog", "blog/Formats", "Spacefast"]
    // Still there, or not a folder: unchanged.
    #expect(FolderEdit.fallback(.folder("blog"), paths: paths, renamed: nil) == .folder("blog"))
    #expect(FolderEdit.fallback(.starred, paths: [], renamed: nil) == .starred)
    #expect(FolderEdit.fallback(.unsorted, paths: [], renamed: nil) == .unsorted)
    // Renamed here: follow it, and a folder inside it follows too.
    #expect(FolderEdit.fallback(.folder("blog/Post formats"), paths: paths, renamed: ("blog/Post formats", "blog/Formats"))
        == .folder("blog/Formats"))
    #expect(FolderEdit.fallback(.folder("old/Formats"), paths: paths, renamed: ("old", "blog")) == .folder("blog/Formats"))
    // Gone some other way: All captures.
    #expect(FolderEdit.fallback(.folder("Archive"), paths: paths, renamed: nil) == .all)
    #expect(FolderEdit.fallback(.folder("Archive"), paths: paths, renamed: ("blog/Post formats", "blog/Formats")) == .all)
    // The rename was refused, so the new path isn't there either.
    #expect(FolderEdit.fallback(.folder("gone"), paths: paths, renamed: ("gone", "Nowhere")) == .all)
}
