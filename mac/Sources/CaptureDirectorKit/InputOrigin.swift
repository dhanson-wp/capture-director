import Foundation

/// What one mouse or key event during a take means.
public enum InputVerdict: Equatable, Sendable {
    /// The recorder posted it.
    case ours
    /// The person at the Mac pressed Escape.
    case escape
    /// Something other than the recorder moved the pointer.
    case userMoved
    /// Another key from somewhere else; it doesn't stop the take.
    case otherKey
}

/// Tells the recorder's own events from everyone else's. The window server stamps each
/// event with the pid that posted it (0 for real hardware), and the recorder also marks
/// its events with `marker` in the user data field; either one makes the event ours.
public func judgeInput(isKey: Bool, keyCode: Int64, sourcePid: Int64, userData: Int64,
                       selfPid: Int64, marker: Int64) -> InputVerdict {
    if sourcePid == selfPid || userData == marker { return .ours }
    if isKey { return keyCode == 53 ? .escape : .otherKey }
    return .userMoved
}
