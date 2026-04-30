import Foundation

struct Attachment: Identifiable, Codable, Equatable {
    let id: UUID
    var originalName: String
    var storedName: String
    var byteSize: Int64
    var addedAt: Date

    init(id: UUID = UUID(), originalName: String, storedName: String, byteSize: Int64, addedAt: Date = Date()) {
        self.id = id
        self.originalName = originalName
        self.storedName = storedName
        self.byteSize = byteSize
        self.addedAt = addedAt
    }

    /// File extension without the dot, lowercased, derived from `originalName`.
    var fileExtension: String {
        (originalName as NSString).pathExtension.lowercased()
    }

    /// True if `fileExtension` is one of the image types we render thumbnails for.
    var isImage: Bool {
        ["jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "bmp"].contains(fileExtension)
    }

    /// 3-character display label for non-image type icons (e.g. "PDF", "DOC").
    var typeLabel: String {
        let ext = fileExtension
        if ext.isEmpty { return "FILE" }
        return String(ext.prefix(4)).uppercased()
    }
}
