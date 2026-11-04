import CoreGraphics
import Testing
@testable import CaptureDirectorKit

private func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }

@Test func shrinksTheWindowOnALaptopDisplay() throws {
    let l = try layout(requested: CGSize(width: 1440, height: 900), visible: CGRect(x: 0, y: 0, width: 1728, height: 1079))
    #expect(close(l.windowSize.width, 1382.4) && close(l.windowSize.height, 864))
    #expect(close(l.sourceRect.width, 1728) && close(l.sourceRect.height, 972))
    #expect(close(l.windowSize.width / l.windowSize.height, 1.6))
    #expect(l.sourceRect.minX >= 0 && l.sourceRect.maxY <= 1079)
}

@Test func keepsTheRequestedSizeWhenItFits() throws {
    let visible = CGRect(x: 0, y: 25, width: 2560, height: 1415)
    let l = try layout(requested: CGSize(width: 1440, height: 900), visible: visible)
    #expect(l.windowSize == CGSize(width: 1440, height: 900))
    #expect(close(l.sourceRect.width, 1800) && close(l.sourceRect.height, 1012.5))
    #expect(close(l.sourceRect.midX, visible.midX) && close(l.sourceRect.midY, visible.midY))
}

@Test func windowCenterMapsToFrameCenter() throws {
    let l = try layout(requested: CGSize(width: 1440, height: 900), visible: CGRect(x: 0, y: 25, width: 2560, height: 1415))
    let center = CGPoint(x: l.windowOrigin.x + l.windowSize.width / 2, y: l.windowOrigin.y + l.windowSize.height / 2)
    let p = toFrame(center, in: l)
    #expect(close(p.x, 960) && close(p.y, 540))
}

@Test func mapsRectsIntoTheFrame() throws {
    let l = try layout(requested: CGSize(width: 1440, height: 900), visible: CGRect(x: 0, y: 0, width: 1800, height: 1012.5))
    let r = toFrame(CGRect(x: 900, y: 506.25, width: 90, height: 45), in: l)
    #expect(close(r.minX, 960) && close(r.minY, 540) && close(r.width, 96) && close(r.height, 48))
}

@Test func throwsWhenTheDisplayIsTooSmall() {
    #expect(throws: FrameError.displayTooSmall) {
        try layout(requested: CGSize(width: 1440, height: 900), visible: CGRect(x: 0, y: 0, width: 900, height: 600))
    }
}
