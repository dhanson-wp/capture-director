import Foundation

public enum CLIError: Error, Equatable, Sendable {
    case notInstalled
    case failed(String)
    /// The CLI ran past its limit and was stopped.
    case timedOut

    /// What to show the person.
    public var message: String {
        switch self {
        case .notInstalled:
            "Capture Director can't find Node or the capture-director CLI anymore. Run capture-director install-app to fix it."
        case .failed(let text):
            text
        case .timedOut:
            "capture-director took too long and was stopped, so nothing changed. If it keeps happening, run capture-director install-app to point the app at an up-to-date CLI."
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

    /// How long a library change may run. A change takes well under a second; a CLI
    /// that doesn't know the command (an old checkout serves the browser library
    /// instead) would otherwise never exit and hold up every change after it.
    public static let writeTimeout: TimeInterval = 60
    /// How long making a smaller copy may run: a long video takes minutes to encode.
    public static let exportTimeout: TimeInterval = 30 * 60

    /// Runs `node cli args…` off the calling actor and returns stdout. Past `timeout`
    /// seconds the CLI is stopped and this throws `CLIError.timedOut`.
    public func run(_ args: [String], timeout: TimeInterval = CLI.writeTimeout) async throws -> Data {
        let config = config, home = home
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try Self.runBlocking(config: config, home: home, args: args, timeout: timeout) })
            }
        }
    }

    private static func runBlocking(config: InstallConfig, home: URL?, args: [String], timeout: TimeInterval) throws -> Data {
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
        let outBox = DataBox(), errBox = DataBox()
        let group = DispatchGroup()
        for (pipe, box) in [(out, outBox), (err, errBox)] {
            group.enter()
            DispatchQueue.global().async {
                box.data = pipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
        }

        // Past the limit: ask it to stop, then make it.
        let timedOut = Flag()
        let stop = DispatchWorkItem {
            guard process.isRunning else { return }
            timedOut.set()
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: stop)
        process.waitUntilExit()
        stop.cancel()
        // Something the CLI started can hold the pipes open after it exits; don't wait on it.
        _ = group.wait(timeout: .now() + 2)

        if timedOut.isSet { throw CLIError.timedOut }
        guard process.terminationStatus == 0 else {
            throw CLIError.failed(message(from: errBox.data))
        }
        return outBox.data
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
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
