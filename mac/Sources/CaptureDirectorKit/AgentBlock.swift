import Foundation

/// The text "Copy for agent" puts on the clipboard.
public enum AgentBlock {
    public static func text(for entries: [LibraryEntry]) -> String {
        entries.map(block).joined(separator: "\n\n")
    }

    private static func block(_ e: LibraryEntry) -> String {
        var lines = ["Capture: \(e.title)", "File: \(e.file)"]
        var facts: [String] = []
        if let d = e.duration, d >= 0 { facts.append(length(d)) }
        if let w = e.width, let h = e.height { facts.append("\(w)x\(h)") }
        if let s = e.size {
            let f = ByteCountFormatter()
            f.countStyle = .file
            facts.append(f.string(fromByteCount: Int64(s)))
        }
        if !facts.isEmpty { lines.append("Length: " + facts.joined(separator: " · ")) }
        if let u = e.url, !u.isEmpty { lines.append("Source site: \(u)") }
        if let s = e.source, !s.isEmpty {
            lines.append("Shot list: \(s)" + (e.shot.flatMap { $0.isEmpty ? nil : " (shot \"\($0)\")" } ?? ""))
        }
        if e.kind == "clip" {
            let dir = (e.file as NSString).deletingLastPathComponent
            lines.append("Click and zoom data: \(dir)/capture.json and zoom-plan.json")
        }
        return lines.joined(separator: "\n")
    }

    private static func length(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        return "\(t / 60):" + String(format: "%02d", t % 60)
    }
}
