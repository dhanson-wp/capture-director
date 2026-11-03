import Foundation

/// The rules behind poster frames and hover scrubbing, with no AVFoundation.
public enum Thumbs {
    /// How many frames the in-memory cache keeps.
    public static let memoryLimit = 300
    /// Hover scrubbing asks for a frame every quarter second, so a sweep
    /// across a card makes a few dozen distinct requests, not hundreds.
    public static let scrubStep = 0.25

    /// The poster frame sits 30% into the clip, like the CLI's cache.
    public static func posterTime(duration: Double?) -> Double {
        guard let duration, duration > 0 else { return 0 }
        return duration * 0.3
    }

    /// The pointer's x across a card of `width`, as a time in the clip,
    /// rounded to quarter seconds and kept short of the last frame.
    public static func scrubTime(x: Double, width: Double, duration: Double?) -> Double {
        guard let duration, duration > 0, width > 0 else { return 0 }
        let fraction = min(max(x / width, 0), 1)
        let rounded = (fraction * duration / scrubStep).rounded() * scrubStep
        let last = max(0, ((duration - 0.1) / scrubStep).rounded(.down) * scrubStep)
        return min(rounded, last)
    }

    /// What identifies one video as it is now: a re-rendered or relocated file
    /// changes it, so nothing cached for the old one is reused.
    public static func sourceKey(id: String, file: String, updated: Date?, size: Int?) -> String {
        "\(id)|\(file)|\(updated?.timeIntervalSince1970 ?? 0)|\(size ?? 0)"
    }

    /// The memory-cache key for one frame; `seconds == nil` is the poster.
    public static func frameKey(id: String, file: String, updated: Date?, size: Int?, seconds: Double?) -> String {
        sourceKey(id: id, file: file, updated: updated, size: size) + "|" + (seconds.map { String($0) } ?? "poster")
    }

    /// `<home>/thumbs/<id>.jpg`, the CLI's poster cache.
    public static func cacheFile(home: URL, id: String) -> URL {
        home.appendingPathComponent("thumbs").appendingPathComponent("\(id).jpg")
    }

    /// A cached poster is usable when it isn't older than the video.
    public static func isFresh(cache: Date?, video: Date?) -> Bool {
        guard let cache else { return false }
        guard let video else { return true }
        return cache >= video
    }
}

/// A least-recently-used cache: reading or writing a key makes it the freshest,
/// and going over `capacity` drops the stalest.
public struct LRUCache<Key: Hashable, Value> {
    public let capacity: Int
    private var values: [Key: Value] = [:]
    private var order: [Key] = []   // stalest first

    public init(capacity: Int) { self.capacity = max(1, capacity) }

    public var count: Int { values.count }

    public subscript(key: Key) -> Value? {
        mutating get {
            guard let v = values[key] else { return nil }
            touch(key)
            return v
        }
        set {
            guard let newValue else {
                values[key] = nil
                order.removeAll { $0 == key }
                return
            }
            values[key] = newValue
            touch(key)
            while order.count > capacity {
                values[order.removeFirst()] = nil
            }
        }
    }

    private mutating func touch(_ key: Key) {
        if let i = order.lastIndex(of: key) { order.remove(at: i) }
        order.append(key)
    }
}
