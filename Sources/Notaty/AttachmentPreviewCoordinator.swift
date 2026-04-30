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
        let attachment = items[index]
        let url = NotesStore.attachmentURL(for: attachment)
        return TitledPreviewItem(url: url, title: attachment.originalName)
    }
}

/// Lets Quick Look display the user-facing original filename instead of the
/// on-disk UUID-based name. The URL still points to the actual file on disk;
/// only the displayed title is overridden.
private final class TitledPreviewItem: NSObject, QLPreviewItem {
    let url: URL
    let title: String

    init(url: URL, title: String) {
        self.url = url
        self.title = title
    }

    var previewItemURL: URL? { url }
    var previewItemTitle: String? { title }
}
