import AppKit
import QuickLookUI

/// Holds the array currently being previewed and serves it to QLPreviewPanel.
/// Implemented as a class because QLPreviewPanel data source is an Obj-C protocol.
final class AttachmentPreviewCoordinator: NSObject, ObservableObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var items: [Attachment] = []
    private var startID: UUID?

    func show(attachments: [Attachment], startAt id: UUID) {
        self.items = attachments
        self.startID = id

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        let url = NotesStore.attachmentURL(for: items[index])
        return url as NSURL
    }
}
