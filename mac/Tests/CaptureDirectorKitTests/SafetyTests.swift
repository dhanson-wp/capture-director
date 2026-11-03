import Foundation
import Testing
@testable import CaptureDirectorKit

@MainActor
private final class Log<T> {
    var items: [T] = []
    func append(_ item: T) { items.append(item) }
}

@MainActor
@Test func serialRunnerRunsJobsOneAtATimeInOrder() async {
    let runner = SerialRunner()
    let log = Log<String>()
    // The first job is slower; without the runner the second would finish first.
    // Main-actor tasks start in the order they're made, so a is handed in first.
    let a = Task { await runner.run {
        log.append("start a")
        try? await Task.sleep(for: .milliseconds(80))
        log.append("end a")
        return 1
    } }
    let b = Task { await runner.run {
        log.append("start b")
        try? await Task.sleep(for: .milliseconds(5))
        log.append("end b")
        return 2
    } }
    let results = [await a.value, await b.value]
    #expect(results == [1, 2])
    #expect(log.items == ["start a", "end a", "start b", "end b"])
}

@MainActor
@Test func serialRunnerKeepsGoingAfterAJobFinishes() async {
    let runner = SerialRunner()
    let log = Log<Int>()
    for i in 1...5 {
        await runner.run { log.append(i) }
    }
    #expect(log.items == [1, 2, 3, 4, 5])
}

@Test func realHomeIsTheDefaultFolderOrInsideIt() {
    let user = "/Users/me"
    #expect(LibraryHome.isReal("/Users/me/.capture-director", userHome: user))
    #expect(LibraryHome.isReal("/Users/me/.capture-director/", userHome: user))
    #expect(LibraryHome.isReal("/Users/me/.capture-director/sub", userHome: user))
    #expect(LibraryHome.isReal("/Users/me/./.capture-director", userHome: user))
    #expect(!LibraryHome.isReal("/tmp/CaptureDirector-self-home", userHome: user))
    #expect(!LibraryHome.isReal("/Users/me/.capture-director-test", userHome: user))
}

@Test func defaultsGuardPutsWindowKeysBackAsTheyWere() {
    let name = "cd-defaults-guard-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("1 2 3 4", forKey: "NSWindow Frame main")
    defaults.set("keep me", forKey: "Other")

    let guardian = DefaultsGuard(defaults, prefixes: ["NSWindow Frame", "NSSplitView Subview Frames"])
    defaults.set("9 9 9 9", forKey: "NSWindow Frame main")
    defaults.set(["a"], forKey: "NSSplitView Subview Frames main")
    defaults.set("changed", forKey: "Other")
    guardian.restore()

    #expect(defaults.string(forKey: "NSWindow Frame main") == "1 2 3 4")
    #expect(defaults.object(forKey: "NSSplitView Subview Frames main") == nil)
    #expect(defaults.string(forKey: "Other") == "changed")
}
