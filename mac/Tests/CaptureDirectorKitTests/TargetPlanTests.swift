import Testing
@testable import CaptureDirectorKit

private let recorder = RunningApp(pid: 10, bundleId: "io.example.app")
private let target = RunningApp(pid: 20, bundleId: "io.example.app")
private let other = RunningApp(pid: 30, bundleId: "io.example.other")

@Test func quitsOtherInstancesButNeverTheRecorder() {
    #expect(instancesToQuit(running: [recorder, target, other], bundleId: "io.example.app", selfPid: 10) == [20])
}

@Test func quitsNothingWhenNoOtherInstanceRuns() {
    #expect(instancesToQuit(running: [other], bundleId: "io.example.app", selfPid: 10).isEmpty)
}

@Test func relaunchesOnlyWhenAnotherInstanceWasRunning() {
    #expect(shouldRelaunchAfter(running: [recorder, target], bundleId: "io.example.app", selfPid: 10))
    #expect(!shouldRelaunchAfter(running: [recorder], bundleId: "io.example.app", selfPid: 10))
}
