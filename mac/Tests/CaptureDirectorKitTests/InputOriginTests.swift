import Testing
@testable import CaptureDirectorKit

private let me: Int64 = 4242
private let marker: Int64 = 0x43_44_52_45_43

@Test func ourPointerMovesAreOursByPid() {
    #expect(judgeInput(isKey: false, keyCode: 0, sourcePid: me, userData: 0, selfPid: me, marker: marker) == .ours)
}

@Test func ourEventsAreOursByMarkerEvenWithoutOurPid() {
    #expect(judgeInput(isKey: false, keyCode: 0, sourcePid: 0, userData: marker, selfPid: me, marker: marker) == .ours)
    #expect(judgeInput(isKey: true, keyCode: 53, sourcePid: 0, userData: marker, selfPid: me, marker: marker) == .ours)
}

@Test func hardwareMovesAreTheUsers() {
    // Real mice report source pid 0 and no user data.
    #expect(judgeInput(isKey: false, keyCode: 0, sourcePid: 0, userData: 0, selfPid: me, marker: marker) == .userMoved)
}

@Test func anotherProcessMovingThePointerCounts() {
    #expect(judgeInput(isKey: false, keyCode: 0, sourcePid: 999, userData: 0, selfPid: me, marker: marker) == .userMoved)
}

@Test func onlyEscapeFromTheUserCancels() {
    #expect(judgeInput(isKey: true, keyCode: 53, sourcePid: 0, userData: 0, selfPid: me, marker: marker) == .escape)
    #expect(judgeInput(isKey: true, keyCode: 0, sourcePid: 0, userData: 0, selfPid: me, marker: marker) == .otherKey)
    #expect(judgeInput(isKey: true, keyCode: 53, sourcePid: me, userData: 0, selfPid: me, marker: marker) == .ours)
}

@Test func someoneElsesClickOrScrollCancels() {
    #expect(judgeInput(isKey: false, keyCode: 0, sourcePid: 0, userData: 0, selfPid: me, marker: marker, isButtonOrScroll: true) == .userPointer)
    #expect(judgeInput(isKey: false, keyCode: 0, sourcePid: me, userData: 0, selfPid: me, marker: marker, isButtonOrScroll: true) == .ours)
    #expect(judgeInput(isKey: false, keyCode: 0, sourcePid: 0, userData: marker, selfPid: me, marker: marker, isButtonOrScroll: true) == .ours)
}

@Test func pointerInputOnlyLandsOnTheTarget() {
    #expect(InputGuard.pointerOnTarget(hitPid: 501, targetPid: 501))
    #expect(!InputGuard.pointerOnTarget(hitPid: 777, targetPid: 501))
    #expect(!InputGuard.pointerOnTarget(hitPid: nil, targetPid: 501))
    #expect(!InputGuard.pointerOnTarget(hitPid: 0, targetPid: 0))
    #expect(InputGuard.pointerBlocked == "Another window was in the way, so the take stopped before clicking it.")
    #expect(InputGuard.focusLost == "Another window took focus during the take.")
}
