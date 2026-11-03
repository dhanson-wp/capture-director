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
}
