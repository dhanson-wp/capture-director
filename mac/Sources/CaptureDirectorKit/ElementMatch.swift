import Foundation

/// A node in an accessibility tree, reduced to what selectors match on.
public protocol ElementNode {
    var role: String? { get }
    var identifier: String? { get }
    var title: String? { get }
    var label: String? { get }
    var value: String? { get }
    var children: [Self] { get }
}

/// Finds the first element matching `target`, searching breadth-first so the shallowest match wins.
public func firstMatch<N: ElementNode>(_ target: Target, in root: N) -> N? {
    var queue = [root]
    var index = 0
    while index < queue.count {
        let node = queue[index]
        index += 1
        if matches(target, node) { return node }
        queue.append(contentsOf: node.children)
    }
    return nil
}

private func matches<N: ElementNode>(_ target: Target, _ node: N) -> Bool {
    switch target {
    case .id(let id):
        return node.identifier == id
    case .roleLabel(let role, let label):
        if let role, !roleMatches(role, node.role) { return false }
        return node.title == label || node.label == label || node.value == label
    }
}

private func roleMatches(_ wanted: String, _ actual: String?) -> Bool {
    guard let actual else { return false }
    return bareRole(wanted).caseInsensitiveCompare(bareRole(actual)) == .orderedSame
}

private func bareRole(_ role: String) -> String {
    role.hasPrefix("AX") ? String(role.dropFirst(2)) : role
}
