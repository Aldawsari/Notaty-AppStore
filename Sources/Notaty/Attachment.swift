import Foundation

struct Attachment: Identifiable, Codable, Equatable {
    let id: UUID
    var originalName: String
    var storedName: String
    var byteSize: Int64
    var addedAt: Date
    /// True if this attachment was created by an in-app voice recording —
    /// either via `RecordingSession.stop()` or `VoiceMigration`. Voice-note
    /// attachments render in `VoiceNoteStripView`; everything else renders
    /// in `AttachmentStripView`.
    var isVoiceNote: Bool

    init(
        id: UUID = UUID(),
        originalName: String,
        storedName: String,
        byteSize: Int64,
        addedAt: Date = Date(),
        isVoiceNote: Bool = false
    ) {
        self.id = id
        self.originalName = originalName
        self.storedName = storedName
        self.byteSize = byteSize
        self.addedAt = addedAt
        self.isVoiceNote = isVoiceNote
    }

    private enum CodingKeys: String, CodingKey {
        case id, originalName, storedName, byteSize, addedAt, isVoiceNote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.originalName = try c.decode(String.self, forKey: .originalName)
        self.storedName = try c.decode(String.self, forKey: .storedName)
        self.byteSize = try c.decode(Int64.self, forKey: .byteSize)
        self.addedAt = try c.decode(Date.self, forKey: .addedAt)
        self.isVoiceNote = try c.decodeIfPresent(Bool.self, forKey: .isVoiceNote) ?? false
    }

    /// File extension without the dot, lowercased, derived from `originalName`.
    var fileExtension: String {
        (originalName as NSString).pathExtension.lowercased()
    }

    /// True if `fileExtension` is one of the image types we render thumbnails for.
    var isImage: Bool {
        ["jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "bmp"].contains(fileExtension)
    }

    /// True if `fileExtension` is one of the audio types the app can
    /// transcribe and play inline.
    var isAudio: Bool {
        ["m4a", "mp3", "wav", "aiff"].contains(fileExtension)
    }

    /// Up-to-4-character uppercase label for non-image type icons.
    var typeLabel: String {
        let ext = fileExtension
        if ext.isEmpty { return "FILE" }
        return String(ext.prefix(4)).uppercased()
    }
}
