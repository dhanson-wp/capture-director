import AppKit

/// Moving clips out of the app as real files.
enum FileDrag {
    /// Puts file URLs on the general pasteboard, so a paste into Finder or
    /// Slack attaches the video itself.
    static func copy(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
    }
}
