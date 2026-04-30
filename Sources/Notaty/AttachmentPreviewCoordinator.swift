import AppKit
import QuickLookUI

/// Holds the attachments currently being previewed and vends them to
/// QLPreviewPanel. Conforms to QLPreviewPanelDataSource + delegate.
///
/// QLPreviewPanel is an app-singleton; the responder chain decides which
/// object answers `acceptsPreviewPanelControl(_:)`. We have AppDelegate
/// answer "yes" and route the panel to this coordinator.
final class AttachmentPreviewCoordinator: NSObject, ObservableObject {
    static let shared = AttachmentPreviewCoordinator()

    private(set) var items: [Attachment] = []
    private var startID: UUID?

    func show(attachments: [Attachment], startAt id: UUID) {
        self.items = attachments
        self.startID = id

        guard let panel = QLPreviewPanel.shared() else { return }

        // Wire dataSource and starting index BEFORE the panel becomes visible.
        // If we orderFront first, the panel briefly opens with no data and
        // flashes the wrong/empty preview before reloadData lands.
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        if let i = items.firstIndex(where: { $0.id == id }) {
            panel.currentPreviewItemIndex = i
        }

        panel.makeKeyAndOrderFront(nil)
    }
}

extension AttachmentPreviewCoordinator: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        let url = NotesStore.attachmentURL(for: items[index])
        return url as NSURL
    }
}
