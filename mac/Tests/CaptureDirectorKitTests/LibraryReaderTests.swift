import Foundation
import Testing
@testable import CaptureDirectorKit

private func write(_ json: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("library.json")
    try json.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@Test func missingFileIsEmpty() throws {
    let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString)/library.json")
    let lib = try LibraryReader.load(from: url)
    #expect(lib == Library(entries: [], folders: [], renames: [:]))
}

@Test func oldEntriesLoadWithBlanks() throws {
    let url = try write("""
    { "entries": [ { "id": "a1", "file": "/x/a.mp4", "title": "A", "kind": "video",
      "starred": false, "notes": "", "added": "2026-10-01T12:00:00.000Z", "project": "Unsorted" } ] }
    """)
    let lib = try LibraryReader.load(from: url)
    let e = try #require(lib.entries.first)
    #expect(e.size == nil)
    #expect(e.url == nil)
    #expect(e.duration == nil)
    #expect(lib.folders == [])
    #expect(e.folder == "")
    #expect(e.added == Date(timeIntervalSince1970: 1_790_856_000))
    #expect(e.isFinal)
    #expect(e.fileURL == URL(fileURLWithPath: "/x/a.mp4"))
}

@Test func badDateDoesNotDropTheLibrary() throws {
    let url = try write("""
    { "entries": [
      { "id": "a", "file": "/a.mp4", "title": "A", "kind": "video", "starred": false, "notes": "", "updated": "yesterday" },
      { "id": "b", "file": "/b.mp4", "title": "B", "kind": "clip", "starred": true, "notes": "n", "updated": "2026-10-01T12:00:00Z" }
    ] }
    """)
    let lib = try LibraryReader.load(from: url)
    #expect(lib.entries.count == 2)
    #expect(lib.entries[0].updated == nil)
    #expect(lib.entries[1].updated != nil)
    #expect(lib.entries[1].isFinal == false)
}

@Test func readsFoldersAndRenames() throws {
    let url = try write(#"{ "entries": [], "folders": ["a", "a/b"], "renames": { "old": "a/b" } }"#)
    let lib = try LibraryReader.load(from: url)
    #expect(lib.folders == ["a", "a/b"])
    #expect(lib.renames == ["old": "a/b"])
}

@Test func installConfigReads() throws {
    let url = try write(#"{ "node": "/n", "cli": "/c", "path": "/usr/bin", "cdHome": null }"#)
    let c = try InstallConfig.load(from: url)
    #expect(c == InstallConfig(node: "/n", cli: "/c", path: "/usr/bin", cdHome: nil))
}

@Test func cdHomeEnvBeatsConfigBeatsDefault() {
    #expect(InstallConfig.effectiveHome(env: ["CD_HOME": "/env"], configHome: "/cfg") == "/env")
    #expect(InstallConfig.effectiveHome(env: ["CD_HOME": ""], configHome: "/cfg") == "/cfg")
    #expect(InstallConfig.effectiveHome(env: [:], configHome: "/cfg") == "/cfg")
    #expect(InstallConfig.effectiveHome(env: [:], configHome: nil) == nil)
}

@Test func libraryFileLocation() {
    #expect(LibraryReader.file(cdHome: "/h").path == "/h/library.json")
    #expect(LibraryReader.file(cdHome: nil).path.hasSuffix("/.capture-director/library.json"))
}
