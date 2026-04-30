import Foundation

enum NoteDirection: String, Codable {
    case auto, ltr, rtl
}

enum NoteType: String, Codable {
    case text
    case voice
}

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var text: String
    var direction: NoteDirection
    var type: NoteType
    var audioFilename: String?
    var attachments: [Attachment]

    init(
        id: UUID = UUID(),
        title: String = "",
        text: String = "",
        direction: NoteDirection = .auto,
        type: NoteType = .text,
        audioFilename: String? = nil,
        attachments: [Attachment] = []
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.direction = direction
        self.type = type
        self.audioFilename = audioFilename
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, text, direction, type, audioFilename, attachments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.text = try c.decode(String.self, forKey: .text)
        self.direction = try c.decodeIfPresent(NoteDirection.self, forKey: .direction) ?? .auto
        self.type = try c.decodeIfPresent(NoteType.self, forKey: .type) ?? .text
        self.audioFilename = try c.decodeIfPresent(String.self, forKey: .audioFilename)
        self.attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
    }
}
