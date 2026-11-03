import Testing
@testable import CaptureDirectorKit

// Seven cards in three columns:
//   0 1 2
//   3 4 5
//   6
private func move(_ from: Int?, _ d: GridMove.Direction, count: Int = 7, columns: Int = 3) -> Int? {
    GridMove.next(from: from, d, count: count, columns: columns)
}

@Test func leftAndRightRunAcrossRows() {
    #expect(move(2, .right) == 3)
    #expect(move(3, .left) == 2)
    #expect(move(0, .left) == 0)
    #expect(move(6, .right) == 6)
}

@Test func upAndDownKeepTheColumn() {
    #expect(move(1, .down) == 4)
    #expect(move(4, .up) == 1)
    #expect(move(0, .up) == 0)
    #expect(move(3, .down) == 6)
    #expect(move(6, .down) == 6)
}

@Test func downOverAShortLastRowLandsOnTheLastCard() {
    #expect(move(4, .down) == 6)
    #expect(move(5, .down) == 6)
    // Already on the last row: nowhere to go.
    #expect(move(5, .down, count: 6) == 5)
}

@Test func homeAndEnd() {
    #expect(move(4, .home) == 0)
    #expect(move(1, .end) == 6)
}

@Test func nothingToStartFrom() {
    #expect(move(nil, .down) == 0)
    #expect(move(nil, .right) == 0)
    #expect(move(nil, .up) == 6)
    #expect(move(nil, .left) == 6)
    #expect(move(9, .down) == 0)
    #expect(move(0, .down, count: 0) == nil)
}

@Test func oneColumnIsAList() {
    #expect(move(1, .down, columns: 1) == 2)
    #expect(move(1, .up, columns: 1) == 0)
    #expect(move(1, .down, columns: 0) == 2)
}

@Test func columnsFitTheWidth() {
    // 208-point cards with 16 between: three need 656.
    #expect(GridMove.columns(width: 656, minimum: 208, spacing: 16) == 3)
    #expect(GridMove.columns(width: 655, minimum: 208, spacing: 16) == 2)
    #expect(GridMove.columns(width: 100, minimum: 208, spacing: 16) == 1)
    #expect(GridMove.columns(width: .infinity, minimum: 208, spacing: 16) == 1)
}
