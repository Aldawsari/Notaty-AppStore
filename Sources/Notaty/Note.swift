import Foundation

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var text: String

    init(id: UUID = UUID(), title: String = "", text: String = "") {
        self.id = id
        self.title = title
        self.text = text
    }
}
