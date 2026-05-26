import Foundation

struct Attachment: Identifiable, Codable, Equatable {
    let id: UUID
    var originalName: String
    var storedName: String
    var byteSize: Int64
    var addedAt: Date

    init(
        id: UUID = UUID(),
        originalName: String,
        storedName: String,
        byteSize: Int64,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.originalName = originalName
        self.storedName = storedName
        self.byteSize = byteSize
        self.addedAt = addedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, originalName, storedName, byteSize, addedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.originalName = try c.decode(String.self, forKey: .originalName)
        self.storedName = try c.decode(String.self, forKey: .storedName)
        self.byteSize = try c.decode(Int64.self, forKey: .byteSize)
        self.addedAt = try c.decode(Date.self, forKey: .addedAt)
    }

    /// File extension without the dot, lowercased, derived from `originalName`.
    var fileExtension: String {
        (originalName as NSString).pathExtension.lowercased()
    }

    /// True if `fileExtension` is one of the image types we render thumbnails for.
    var isImage: Bool {
        ["jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "bmp"].contains(fileExtension)
    }

    /// Up-to-4-character uppercase label for non-image type icons.
    var typeLabel: String {
        let ext = fileExtension
        if ext.isEmpty { return "FILE" }
        return String(ext.prefix(4)).uppercased()
    }
}
