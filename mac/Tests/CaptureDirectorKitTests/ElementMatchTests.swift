import Testing
@testable import CaptureDirectorKit

private struct Node: ElementNode {
    var role: String? = nil
    var identifier: String? = nil
    var title: String? = nil
    var label: String? = nil
    var value: String? = nil
    var children: [Node] = []
}

private let tree = Node(role: "AXWindow", children: [
    Node(role: "AXGroup", children: [
        Node(role: "AXStaticText", value: "Starred", children: []),
        Node(role: "AXButton", identifier: "inspector"),
    ]),
    Node(role: "AXRow", label: "Starred"),
    Node(role: "AXButton", title: "Share"),
])

@Test func matchesAnIdentifierExactly() {
    #expect(firstMatch(.id("inspector"), in: tree)?.role == "AXButton")
    #expect(firstMatch(.id("inspect"), in: tree) == nil)
}

@Test func matchesRoleAndLabelWithOrWithoutTheAXPrefix() {
    #expect(firstMatch(.roleLabel(role: "row", label: "Starred"), in: tree)?.role == "AXRow")
    #expect(firstMatch(.roleLabel(role: "AXRow", label: "Starred"), in: tree)?.role == "AXRow")
    #expect(firstMatch(.roleLabel(role: "button", label: "Starred"), in: tree) == nil)
}

@Test func aBareLabelMatchesTitleDescriptionOrValueOfAnyRole() {
    #expect(firstMatch(.roleLabel(role: nil, label: "Share"), in: tree)?.role == "AXButton")
    #expect(firstMatch(.roleLabel(role: nil, label: "Starred"), in: tree)?.role == "AXRow")
}

@Test func theShallowerMatchWins() {
    // The value match is nested a level deeper than the row, so the row wins.
    #expect(firstMatch(.roleLabel(role: nil, label: "Starred"), in: tree)?.label == "Starred")
}

@Test func aMissReturnsNil() {
    #expect(firstMatch(.roleLabel(role: nil, label: "Nope"), in: tree) == nil)
}
