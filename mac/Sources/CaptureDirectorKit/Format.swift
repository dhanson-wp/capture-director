import Foundation

/// Text formats that must not change with the system locale.
public enum Format {
    /// Decimal units (1 KB = 1000 bytes), one fraction digit from KB up, "." always.
    public static func size(_ bytes: Int) -> String {
        if bytes < 1000 { return "\(max(bytes, 0)) B" }
        let units = ["KB", "MB", "GB"]
        var value = Double(bytes) / 1000
        var i = 0
        while value >= 999.95 && i < units.count - 1 { value /= 1000; i += 1 }
        let tenths = Int((value * 10).rounded())
        return "\(tenths / 10).\(tenths % 10) \(units[i])"
    }

    /// A clip's length as m:ss, or h:mm:ss from an hour up. Rounds to whole seconds.
    public static func length(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        return h > 0 ? "\(h):\(two(m)):\(two(s))" : "\(m):\(two(s))"
    }
}
