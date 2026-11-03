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
        guard let image = try? await source(for: entry).frame(at: time, scrub: seconds != nil) else {
            return nil
        }
        memory[key] = image
        return image
    }

    private func source(for entry: LibraryEntry) -> FrameSource {
        let key = Thumbs.sourceKey(id: entry.id, file: entry.file, updated: entry.updated, size: entry.size)
        if let s = generators[key] { return s }
        let s = FrameSource(entry.fileURL)
        generators[key] = s
        return s
    }

    private static func key(_ e: LibraryEntry, _ seconds: Double?) -> String {
        Thumbs.frameKey(id: e.id, file: e.file, updated: e.updated, size: e.size, seconds: seconds)
    }

    private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

/// One video's frame generators. Each is configured once here and never
/// changed, so concurrent calls can't disturb each other: posters use the
/// default tolerance, scrubbing a looser one so the nearest frame comes back fast.
private nonisolated final class FrameSource: @unchecked Sendable {
    private let poster: AVAssetImageGenerator
    private let scrub: AVAssetImageGenerator

    init(_ url: URL) {
        let asset = AVURLAsset(url: url)
        func make(_ tolerance: CMTime?) -> AVAssetImageGenerator {
            let g = AVAssetImageGenerator(asset: asset)
            g.appliesPreferredTrackTransform = true
            g.maximumSize = CGSize(width: 640, height: 640)
            if let tolerance {
                g.requestedTimeToleranceBefore = tolerance
                g.requestedTimeToleranceAfter = tolerance
            }
            return g
        }
        poster = make(nil)
        scrub = make(CMTime(seconds: 0.125, preferredTimescale: 600))
    }

    func frame(at seconds: Double, scrub isScrub: Bool) async throws -> CGImage {
        let g = isScrub ? scrub : poster
        return try await g.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }
}
