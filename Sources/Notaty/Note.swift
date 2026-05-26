import Foundation

enum NoteDirection: String, Codable {
    case auto, ltr, rtl
}

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var text: String
    var direction: NoteDirection

    init(
        id: UUID = UUID(),
        title: String = "",
        text: String = "",
        direction: NoteDirection = .auto
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.direction = direction
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, text, direction
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.text = try c.decode(String.self, forKey: .text)
        self.direction = try c.decodeIfPresent(NoteDirection.self, forKey: .direction) ?? .auto
    }
}
