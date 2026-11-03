import Foundation

public enum CLIError: Error, Equatable, Sendable {
    case notInstalled
    case failed(String)

    /// What to show the person.
    public var message: String {
        switch self {
        case .notInstalled:
            "Capture Director can't find Node or the capture-director CLI anymore. Run capture-director install-app to fix it."
        case .failed(let text):
            text
        }
    }
}

/// Runs the capture-director CLI. Every library change goes through here.
public struct CLI: Sendable {
    public let config: InstallConfig
    /// The library home the CLI writes to; the same one the app reads.
    public let home: URL?

    public init(config: InstallConfig, home: URL? = nil) {
        self.config = config
        self.home = home
    }

    /// Runs `node cli args…` off the calling actor and returns stdout.
    public func run(_ args: [String]) async throws -> Data {
        let config = config, home = home
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try Self.runBlocking(config: config, home: home, args: args) })
            }
        }
    }

    private static func runBlocking(config: InstallConfig, home: URL?, args: [String]) throws -> Data {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: config.node), fm.fileExists(atPath: config.cli) else {
            throw CLIError.notInstalled
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.node)
        process.arguments = [config.cli] + args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = config.path
        if let home { env["CD_HOME"] = home.path } else if let h = config.cdHome, !h.isEmpty { env["CD_HOME"] = h }
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { throw CLIError.notInstalled }

        // Drain both pipes at once so a chatty child can't fill one and stall.
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errBox.data = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CLIError.failed(message(from: errBox.data))
        }
        return stdout
    }

    private final class DataBox: @unchecked Sendable { var data = Data() }

    /// The text after `[capture-director] `, else the last line of stderr.
    static func message(from stderr: Data) -> String {
        let lines = String(decoding: stderr, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let prefix = "[capture-director] "
        if let line = lines.last(where: { $0.hasPrefix(prefix) }) { return String(line.dropFirst(prefix.count)) }
        return lines.last ?? "Something went wrong running capture-director."
    }
}
