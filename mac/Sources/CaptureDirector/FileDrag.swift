import AppKit
import CaptureDirectorKit
import SwiftUI

/// Moving clips out of the app as real files.
enum FileDrag {
    /// Puts file URLs on the general pasteboard, so a paste into Finder or
    /// Slack attaches the video itself.
    static func copy(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
    }

    /// One dragging item per video, each with the file URL as its pasteboard
    /// writer, so Finder and browser upload boxes get every file. The icons
    /// fan out a little from `origin`, the pointer in window coordinates.
    static func dragItems(_ entries: [LibraryEntry], at origin: NSPoint = .zero) -> [NSDraggingItem] {
        let side: CGFloat = 64
        return entries.enumerated().map { index, entry in
            let item = NSDraggingItem(pasteboardWriter: entry.fileURL as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: entry.file)
            let step = CGFloat(min(index, 4)) * 6
            item.setDraggingFrame(NSRect(x: origin.x - side / 2 + step, y: origin.y - side / 2 - step,
                                         width: side, height: side),
                                  contents: icon)
            return item
        }
    }

    /// Starts an AppKit drag of every entry's file from the mouse event being handled.
    /// SwiftUI's `.draggable` carries one item, so several selected captures go this way.
    @discardableResult
    static func begin(_ entries: [LibraryEntry]) -> Bool {
        guard !entries.isEmpty, let event = NSApp.currentEvent,
              event.type == .leftMouseDragged || event.type == .leftMouseDown,
              let view = event.window?.contentView else { return false }
        let point = view.convert(event.locationInWindow, from: nil)
        view.beginDraggingSession(with: dragItems(entries, at: point), event: event, source: Source.shared)
        return true
    }

    /// Copies out of the app; never moves the original video.
    private final class Source: NSObject, NSDraggingSource {
        static let shared = Source()
        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .copy
        }
    }
}

extension View {
    /// Drags these captures out as files, leaving out any whose file is gone. One capture uses `.draggable` with
    /// the file URL (checked into WordPress, YouTube, GitHub, Slack, and
    /// Finder); several start one AppKit session with a dragging item per file.
    /// Put it inside a view that keeps its own state: switching between one
    /// and several rebuilds what it wraps.
    @ViewBuilder
    func fileDrag(_ entries: [LibraryEntry]) -> some View {
        // A capture whose file is gone has nothing to hand over, so it doesn't drag at all.
        let files = entries.filter(\.fileExists)
        if files.count == 1, let entry = files.first {
            draggable(entry.fileURL)
        } else if files.count > 1 {
            modifier(MultiFileDrag(entries: files))
        } else {
            self
        }
    }
}

/// Starts one AppKit drag of every file once the pointer moves 4 points.
/// Turned off, it stays attached, so the view keeps its identity and state.
struct MultiFileDrag: ViewModifier {
    let entries: [LibraryEntry]
    var enabled = true
    @GestureState private var started = false

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 4)
                .updating($started) { _, started, _ in
                    guard !started else { return }
                    started = true
                    FileDrag.begin(entries.filter(\.fileExists))
                },
            isEnabled: enabled
        )
    }
}
