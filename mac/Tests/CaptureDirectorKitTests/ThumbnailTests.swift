import Foundation
import Testing
@testable import CaptureDirectorKit

@Test func posterFrameIsThirtyPercentIn() {
    #expect(Thumbs.posterTime(duration: 10) == 3)
    #expect(Thumbs.posterTime(duration: 45) == 13.5)
    #expect(Thumbs.posterTime(duration: nil) == 0)
    #expect(Thumbs.posterTime(duration: -4) == 0)
}

@Test func scrubTimeFollowsThePointerInQuarterSeconds() {
    // Left edge, middle, and a spot that has to round.
    #expect(Thumbs.scrubTime(x: 0, width: 200, duration: 24) == 0)
    #expect(Thumbs.scrubTime(x: 100, width: 200, duration: 24) == 12)
    #expect(Thumbs.scrubTime(x: 50, width: 200, duration: 9) == 2.25)
    #expect(Thumbs.scrubTime(x: 61, width: 200, duration: 9) == 2.75) // 2.745 rounds to 2.75
    for x in stride(from: 0.0, through: 200, by: 7) {
        let t = Thumbs.scrubTime(x: x, width: 200, duration: 13.37)
        #expect((t * 4).rounded() == t * 4)
    }
}

@Test func scrubTimeStaysInsideTheClip() {
    #expect(Thumbs.scrubTime(x: -30, width: 200, duration: 24) == 0)
    // The very end of a clip has no frame to ask for; stop a step short.
    #expect(Thumbs.scrubTime(x: 200, width: 200, duration: 24) == 23.75)
    #expect(Thumbs.scrubTime(x: 900, width: 200, duration: 24) == 23.75)
    #expect(Thumbs.scrubTime(x: 100, width: 0, duration: 24) == 0)
    #expect(Thumbs.scrubTime(x: 100, width: 200, duration: 0.2) == 0)
    #expect(Thumbs.scrubTime(x: 100, width: 200, duration: nil) == 0)
}

@Test func cacheFileIsFreshWhenNotOlderThanTheVideo() {
    let video = Date(timeIntervalSince1970: 1_000)
    #expect(Thumbs.isFresh(cache: Date(timeIntervalSince1970: 1_001), video: video))
    #expect(Thumbs.isFresh(cache: video, video: video))
    #expect(!Thumbs.isFresh(cache: Date(timeIntervalSince1970: 999), video: video))
    #expect(!Thumbs.isFresh(cache: nil, video: video))
    // A video we can't stat can't be checked, so the cache file is trusted.
    #expect(Thumbs.isFresh(cache: video, video: nil))
}

@Test func thumbnailFileLivesUnderThumbsInTheHome() {
    #expect(Thumbs.cacheFile(home: URL(fileURLWithPath: "/tmp/cd"), id: "abc").path == "/tmp/cd/thumbs/abc.jpg")
}

@Test func lruKeepsTheMostRecentlyUsed() {
    var lru = LRUCache<String, Int>(capacity: 3)
    lru["a"] = 1; lru["b"] = 2; lru["c"] = 3
    #expect(lru["a"] == 1)          // a is now the freshest
    lru["d"] = 4                    // evicts b, the stalest
    #expect(lru["b"] == nil)
    #expect(lru["a"] == 1 && lru["c"] == 3 && lru["d"] == 4)
    #expect(lru.count == 3)
    lru["c"] = 30                   // overwriting doesn't grow it
    #expect(lru.count == 3 && lru["c"] == 30)
}

@Test func lruEvictsAtThreeHundred() {
    var lru = LRUCache<Int, Int>(capacity: Thumbs.memoryLimit)
    #expect(Thumbs.memoryLimit == 300)
    for i in 0..<400 { lru[i] = i }
    #expect(lru.count == 300)
    #expect(lru[99] == nil && lru[100] == 100 && lru[399] == 399)
}

@Test func cacheKeysChangeWhenTheVideoDoes() {
    let d = Date(timeIntervalSince1970: 500)
    let base = Thumbs.frameKey(id: "a", file: "/v/a.mp4", updated: d, size: 10, seconds: nil)
    #expect(base == Thumbs.frameKey(id: "a", file: "/v/a.mp4", updated: d, size: 10, seconds: nil))
    #expect(base != Thumbs.frameKey(id: "a", file: "/w/a.mp4", updated: d, size: 10, seconds: nil))   // relocated
    #expect(base != Thumbs.frameKey(id: "a", file: "/v/a.mp4", updated: d.addingTimeInterval(1), size: 10, seconds: nil))
    #expect(base != Thumbs.frameKey(id: "a", file: "/v/a.mp4", updated: d, size: 11, seconds: nil))   // re-rendered
    #expect(base != Thumbs.frameKey(id: "a", file: "/v/a.mp4", updated: d, size: 10, seconds: 1.5))
    #expect(Thumbs.sourceKey(id: "a", file: "/v/a.mp4", updated: d, size: 10) != Thumbs.sourceKey(id: "a", file: "/v/a.mp4", updated: d, size: 11))
}
