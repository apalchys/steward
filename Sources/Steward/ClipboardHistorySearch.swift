import Foundation

enum ClipboardHistorySearch {
    static func filter(records: [ClipboardHistoryRecord], query: String) -> [ClipboardHistoryRecord] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return records
        }

        return records.filter { record in
            record.text.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
}
