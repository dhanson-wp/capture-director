import Foundation
import Testing
@testable import CaptureDirectorKit

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func bump() { lock.lock(); n += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
}

@Test func atomicReplaceFiresTheWatcher() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let file = dir.appendingPathComponent("library.json")
    let flag = Flag()
    let watcher = LibraryWatcher(file: file) { flag.bump() }
    watcher.start()
    defer { watcher.stop() }
    #expect(FileManager.default.fileExists(atPath: dir.path))   // start() makes the folder

    let tmp = dir.appendingPathComponent("library.json.tmp")
    try "{}".write(to: tmp, atomically: false, encoding: .utf8)
    _ = try FileManager.default.replaceItemAt(file, withItemAt: tmp)   // rename over, like the CLI

    for _ in 0..<20 where flag.count == 0 { try await Task.sleep(for: .milliseconds(50)) }
    #expect(flag.count >= 1)
}
