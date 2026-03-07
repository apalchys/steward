import Foundation

struct ClipboardHistoryRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let capturedAt: Date
    let text: String
    let size: Int

    init(id: UUID = UUID(), capturedAt: Date, text: String, size: Int? = nil) {
        self.id = id
        self.capturedAt = capturedAt
        self.text = text
        self.size = size ?? text.utf8.count
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case capturedAt
        case text
        case size
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        text = try container.decode(String.self, forKey: .text)
        _ = try container.decode(Int.self, forKey: .size)
        size = text.utf8.count
    }
}
