import AppKit
import QuickLookUI

/// Space on the selection: the system Quick Look panel, fed from the library.
@MainActor
final class QuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLook()

    private var urls: [URL] = []
    private var provider: (() -> [URL])?

    private var panel: QLPreviewPanel? { QLPreviewPanel.shared() }
    var isVisible: Bool { QLPreviewPanel.sharedPreviewPanelExists() && panel?.isVisible == true }

    /// Opens the panel on what `provider` returns, or closes it when it's already open.
    func toggle(_ provider: @escaping () -> [URL]) {
        if isVisible {
            panel?.orderOut(nil)
            return
        }
        self.provider = provider
        urls = provider()
        guard !urls.isEmpty, let panel else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    /// The selection moved while the panel is open; follow it, like Finder.
    func selectionChanged() {
        guard isVisible, let provider else { return }
        urls = provider()
        if urls.isEmpty { panel?.orderOut(nil) } else { panel?.reloadData() }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls[index] as NSURL
    }
}
