import Foundation

/// What one mouse or key event during a take means.
public enum InputVerdict: Equatable, Sendable {
    /// The recorder posted it.
    case ours
    /// The person at the Mac pressed Escape.
    case escape
    /// Something other than the recorder moved the pointer.
    case userMoved
    /// Something other than the recorder clicked or scrolled.
    case userPointer
    /// Another key from somewhere else; it doesn't stop the take.
    case otherKey
}

/// Tells the recorder's own events from everyone else's. The window server stamps each
/// event with the pid that posted it (0 for real hardware), and the recorder also marks
/// its events with `marker` in the user data field; either one makes the event ours.
/// `isButtonOrScroll` marks a mouse button press or a scroll rather than a move.
public func judgeInput(isKey: Bool, keyCode: Int64, sourcePid: Int64, userData: Int64,
                       selfPid: Int64, marker: Int64, isButtonOrScroll: Bool = false) -> InputVerdict {
    if sourcePid == selfPid || userData == marker { return .ours }
    if isKey { return keyCode == 53 ? .escape : .otherKey }
    return isButtonOrScroll ? .userPointer : .userMoved
}

/// What the recorder checks before it sends input, so nothing lands outside the target app.
public enum InputGuard {
    public static let pointerBlocked = "Another window was in the way, so the take stopped before clicking it."
    public static let focusLost = "Another window took focus during the take."

    /// True when the element under the pointer belongs to the target. No element, or no target, is a no.
    public static func pointerOnTarget(hitPid: Int32?, targetPid: Int32) -> Bool {
        guard let hitPid, targetPid > 0 else { return false }
        return hitPid == targetPid
    }
}
