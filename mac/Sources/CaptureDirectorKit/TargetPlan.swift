import Foundation

/// A running process, as much as the recorder needs to know about it.
public struct RunningApp: Equatable, Sendable {
    public var pid: Int32
    public var bundleId: String?

    public init(pid: Int32, bundleId: String?) {
        self.pid = pid
        self.bundleId = bundleId
    }
}

/// The processes to quit before launching the target fresh: every instance of the bundle ID except the recorder itself.
public func instancesToQuit(running: [RunningApp], bundleId: String, selfPid: Int32) -> [Int32] {
    running.filter { $0.bundleId == bundleId && $0.pid != selfPid }.map(\.pid)
}

/// True when the recorder is not the only instance of the bundle ID, so quitting others and relaunching is safe and needed.
/// False when only the recorder runs under that bundle ID: there's nothing to quit, and quitting would end the recording.
public func shouldRelaunchAfter(running: [RunningApp], bundleId: String, selfPid: Int32) -> Bool {
    !instancesToQuit(running: running, bundleId: bundleId, selfPid: selfPid).isEmpty
}
