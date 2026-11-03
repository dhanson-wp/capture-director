import Foundation
import Testing
@testable import CaptureDirectorKit

private func scratch() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// A fake `node` script plus a fake CLI file, and a config pointing at them.
private func fake(_ body: String) throws -> InstallConfig {
    let dir = try scratch()
    let node = dir.appendingPathComponent("node")
    try "#!/bin/sh\n\(body)\n".write(to: node, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
    let cli = dir.appendingPathComponent("capture-director.js")
    try "".write(to: cli, atomically: true, encoding: .utf8)
    return InstallConfig(node: node.path, cli: cli.path, path: "/usr/bin:/bin", cdHome: nil)
}

@Test func cliPassesArgsAndReturnsStdout() async throws {
    let cli = CLI(config: try fake(#"echo "$@""#))
    let data = try await cli.run(["library", "forget", "x"])
    let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(text.hasSuffix("library forget x"))
}

@Test func cliErrorUsesTheMessage() async throws {
    let cli = CLI(config: try fake(#"echo "[capture-director] No capture with id x" >&2; exit 1"#))
    await #expect(throws: CLIError.failed("No capture with id x")) {
        try await cli.run(["library", "forget", "x"])
    }
}

@Test func cliMissingNodeGivesReinstallMessage() async throws {
    var config = try fake("true")
    config.node = "/nonexistent/node-\(UUID().uuidString)"
    let cli = CLI(config: config)
    await #expect(throws: CLIError.notInstalled) { try await cli.run(["library"]) }
    #expect(CLIError.notInstalled.message == "Capture Director can't find Node or the capture-director CLI anymore. Run capture-director install-app to fix it.")
}

@Test func cliGetsTheStoresHomeAsCDHome() async throws {
    let cli = CLI(config: try fake(#"echo "$CD_HOME""#), home: URL(fileURLWithPath: "/tmp/some-home"))
    let text = String(decoding: try await cli.run([]), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(text == "/tmp/some-home")
}
