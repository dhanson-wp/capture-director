import Foundation

/// Quoting for commands people paste into Terminal.
public enum Shell {
    private static let plain = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")

    /// The word as it is when it's safe, else in single quotes ('\'' for a quote inside).
    public static func quote(_ s: String) -> String {
        if !s.isEmpty, s.unicodeScalars.allSatisfy({ plain.contains($0) }) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

extension LibraryEntry {
    /// `capture-director record <source> --only <shot>`, for a clip that has both.
    public var recordAgainCommand: String? {
        guard let source, !source.isEmpty, let shot, !shot.isEmpty else { return nil }
        return "capture-director record \(Shell.quote(source)) --only \(Shell.quote(shot))"
    }
}

/// Which captures a drag carries.
public enum DragSet {
    /// The whole selection, in screen order, when the dragged capture is in it;
    /// otherwise just the dragged capture.
    public static func entries(dragging: LibraryEntry, selection: Set<String>, in order: [LibraryEntry]) -> [LibraryEntry] {
        guard selection.contains(dragging.id) else { return [dragging] }
        return order.filter { selection.contains($0.id) }
    }
}

/// Rules for actions on several captures at once.
public enum Bulk {
    /// Star stars them all unless every one is starred already; then it unstars.
    public static func starTarget(_ entries: [LibraryEntry]) -> Bool {
        !entries.allSatisfy(\.starred) || entries.isEmpty
    }
}
