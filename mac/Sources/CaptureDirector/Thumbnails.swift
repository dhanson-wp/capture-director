import AVFoundation
import CaptureDirectorKit
import Foundation
import ImageIO

/// Poster frames and hover-scrub frames. Everything here runs off the main
/// actor; callers `await` an image and never wait on the main thread.
///
/// A poster (`seconds == nil`) comes from the CLI's `<home>/thumbs/<id>.jpg`
/// when that file is newer than the video, else from the video itself.
/// Every image lands in an in-memory LRU of 300.
actor ThumbnailCache {
    private let home: URL
    private var memory = LRUCache<String, CGImage>(capacity: Thumbs.memoryLimit)
    /// A scrub asks for dozens of frames from one video; keep its generator warm.
    private var generators = LRUCache<String, FrameSource>(capacity: 8)

    init(home: URL) {
        self.home = home
    }

    /// The frame at `seconds`, or the poster frame when `seconds` is nil.
    /// Nil when the video is missing or can't be read, so the card keeps its placeholder.
    func image(for entry: LibraryEntry, at seconds: Double?) async -> CGImage? {
        let key = Self.key(entry, seconds)
        if let hit = memory[key] { return hit }
        let video = entry.fileURL
        guard let videoDate = Self.modified(video) else { return nil }
        if Task.isCancelled { return nil }

        if seconds == nil {
            let file = Thumbs.cacheFile(home: home, id: entry.id)
            if Thumbs.isFresh(cache: Self.modified(file), video: videoDate),
               let image = Self.decode(file) {
                memory[key] = image
                return image
            }
        }

        let time = seconds ?? Thumbs.posterTime(duration: entry.duration)
        // Posters can land anywhere near the mark; a scrub wants the nearest
        // frame fast, not the exact one.
        let tolerance = seconds == nil ? 0.5 : 0.125
        guard let image = try? await source(for: entry).frame(at: time, tolerance: tolerance) else {
            return nil
        }
        memory[key] = image
        return image
    }

    private func source(for entry: LibraryEntry) -> FrameSource {
        let key = "\(entry.id)|\(entry.file)"
        if let s = generators[key] { return s }
        let s = FrameSource(entry.fileURL)
        generators[key] = s
        return s
    }

    /// Tied to the entry's last change, so a re-rendered video doesn't show an old frame.
    private static func key(_ entry: LibraryEntry, _ seconds: Double?) -> String {
        let changed = entry.updated?.timeIntervalSince1970 ?? 0
        return "\(entry.id)|\(changed)|\(entry.size ?? 0)|\(seconds.map { String($0) } ?? "poster")"
    }

    private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

/// One video's frame generator. AVAssetImageGenerator serializes its own work,
/// and the cache only ever hands one source to one call at a time per frame.
private nonisolated final class FrameSource: @unchecked Sendable {
    private let generator: AVAssetImageGenerator

    init(_ url: URL) {
        generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
    }

    func frame(at seconds: Double, tolerance: Double) async throws -> CGImage {
        let slack = CMTime(seconds: tolerance, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = slack
        generator.requestedTimeToleranceAfter = slack
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }
}
