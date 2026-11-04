import CoreGraphics
import Foundation

/// Where the target window goes on screen and which part of the screen is recorded.
/// All values are in global screen points with a top-left origin.
public struct FrameLayout: Equatable, Sendable {
    public var windowSize: CGSize
    public var windowOrigin: CGPoint
    /// The 16:9 region that becomes the 1920x1080 frame.
    public var sourceRect: CGRect

    public init(windowSize: CGSize, windowOrigin: CGPoint, sourceRect: CGRect) {
        self.windowSize = windowSize
        self.windowOrigin = windowOrigin
        self.sourceRect = sourceRect
    }
}

public enum FrameError: Error, LocalizedError, Equatable {
    case displayTooSmall

    public var errorDescription: String? {
        switch self {
        case .displayTooSmall: return "The display is too small to record this app. Try a larger display or a smaller window."
        }
    }
}

/// Leave room for shadows without changing the default wide-window framing.
private let windowShare: CGFloat = 0.8
private let windowHeightShare: CGFloat = 0.9
private let minimumWindow = CGSize(width: 760, height: 480)

/// Fits a 16:9 source rect, centered in `visible`, around the requested window size.
/// When the rect doesn't fit, the window shrinks and keeps its aspect ratio.
public func layout(requested: CGSize, visible: CGRect) throws -> FrameLayout {
    guard requested.width > 0, requested.height > 0, visible.width > 0, visible.height > 0 else {
        throw FrameError.displayTooSmall
    }
    let sourceWidth = max(requested.width / windowShare, requested.height / windowHeightShare * 16 / 9)
    let sourceHeight = sourceWidth * 9 / 16
    let scale = min(1, visible.width / sourceWidth, visible.height / sourceHeight)
    let window = CGSize(width: requested.width * scale, height: requested.height * scale)
    guard window.width >= minimumWindow.width, window.height >= minimumWindow.height else {
        throw FrameError.displayTooSmall
    }
    let source = CGSize(width: sourceWidth * scale, height: sourceHeight * scale)
    let center = CGPoint(x: visible.midX, y: visible.midY)
    let sourceRect = CGRect(x: center.x - source.width / 2, y: center.y - source.height / 2, width: source.width, height: source.height)
    let origin = CGPoint(x: center.x - window.width / 2, y: center.y - window.height / 2)
    return FrameLayout(windowSize: window, windowOrigin: origin, sourceRect: sourceRect)
}

/// Maps a screen point into the 1920x1080 frame.
public func toFrame(_ p: CGPoint, in layout: FrameLayout) -> CGPoint {
    let k = 1920 / layout.sourceRect.width
    return CGPoint(x: (p.x - layout.sourceRect.minX) * k, y: (p.y - layout.sourceRect.minY) * k)
}

/// Maps a screen rect (a focus box, say) into the 1920x1080 frame.
public func toFrame(_ r: CGRect, in layout: FrameLayout) -> CGRect {
    let k = 1920 / layout.sourceRect.width
    let origin = toFrame(r.origin, in: layout)
    return CGRect(x: origin.x, y: origin.y, width: r.width * k, height: r.height * k)
}
