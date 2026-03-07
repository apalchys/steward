import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var store: ClipboardHistoryStore

    @State private var selectedRecordID: ClipboardHistoryRecord.ID?
    @State private var autoSelectNewest = true
    @State private var previousVisibleIDs: [ClipboardHistoryRecord.ID] = []
    @State private var isProgrammaticSelectionChange = false
    @State private var showClearAllConfirmation = false
    @State private var searchQuery = ""

    private var filteredRecords: [ClipboardHistoryRecord] {
        ClipboardHistorySearch.filter(records: store.records, query: searchQuery)
    }

    private var visibleRecords: [ClipboardHistoryRecord] {
        Array(filteredRecords.reversed())
    }

    private var hasSearchQuery: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedRecord: ClipboardHistoryRecord? {
        guard let selectedRecordID else {
            return nil
        }

        return visibleRecords.first(where: { $0.id == selectedRecordID })
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            if visibleRecords.isEmpty {
                emptyState
            } else {
                GeometryReader { geometry in
                    let maxListWidth = max(220, geometry.size.width / 3)

                    HSplitView {
                        recordsList(maxWidth: maxListWidth)
                        detailsPane
                            .frame(minWidth: max(300, geometry.size.width - maxListWidth))
                    }
                }
            }

            if let errorMessage = store.lastErrorMessage {
                Divider()
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 760, minHeight: 460)
        .onAppear {
            synchronizeSelection(with: visibleRecords.map(\.id))
        }
        .onChange(of: visibleRecords.map(\.id)) { _, newIDs in
            synchronizeSelection(with: newIDs)
        }
        .onChange(of: selectedRecordID) { _, newSelection in
            guard !isProgrammaticSelectionChange,
                let newestRecordID = visibleRecords.first?.id
            else {
                return
            }

            autoSelectNewest = (newSelection == newestRecordID)
        }
        .alert("Clear clipboard history?", isPresented: $showClearAllConfirmation) {
            Button("Clear All", role: .destructive) {
                autoSelectNewest = true
                setSelection(nil)
                store.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all saved clipboard records.")
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("Clipboard History")
                .font(.title3)
                .fontWeight(.semibold)

            Text(recordCountSummary)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search entries", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            Spacer()

            Button("Clear All", role: .destructive) {
                showClearAllConfirmation = true
            }
            .disabled(store.records.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func recordsList(maxWidth: CGFloat) -> some View {
        List(selection: $selectedRecordID) {
            ForEach(visibleRecords) { record in
                ClipboardHistoryRow(record: record) {
                    deleteRecord(record.id)
                }
                .tag(record.id)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .frame(minWidth: 220, idealWidth: min(360, maxWidth), maxWidth: maxWidth)
    }

    private var detailsPane: some View {
        Group {
            if let selectedRecord {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Captured: \(Self.detailDateFormatter.string(from: selectedRecord.capturedAt))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Size: \(selectedRecord.size) bytes")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ScrollView {
                        Text(selectedRecord.text)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack {
                    Spacer()
                    Text("Select a clipboard record to view details.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Text(emptyStateTitle)
                .font(.title3)
                .fontWeight(.semibold)
            Text(emptyStateDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func synchronizeSelection(with currentIDs: [ClipboardHistoryRecord.ID]) {
        defer { previousVisibleIDs = currentIDs }

        guard !currentIDs.isEmpty else {
            setSelection(nil)
            autoSelectNewest = true
            return
        }

        if selectedRecordID == nil {
            setSelection(currentIDs[0])
            return
        }

        let countIncreased = currentIDs.count > previousVisibleIDs.count
        let newestChanged = currentIDs.first != previousVisibleIDs.first
        if countIncreased, newestChanged, autoSelectNewest {
            setSelection(currentIDs[0])
            return
        }

        if let selectedRecordID, !currentIDs.contains(selectedRecordID) {
            setSelection(currentIDs[0])
        }
    }

    private func deleteRecord(_ id: ClipboardHistoryRecord.ID) {
        let ids = visibleRecords.map(\.id)
        guard let index = ids.firstIndex(of: id) else {
            return
        }

        if selectedRecordID == id {
            let nextIndex = index + 1
            let replacementID =
                nextIndex < ids.count ? ids[nextIndex] : (index > 0 ? ids[index - 1] : nil)
            setSelection(replacementID)
        }

        store.deleteRecord(id: id)
    }

    private func setSelection(_ id: ClipboardHistoryRecord.ID?) {
        isProgrammaticSelectionChange = true
        selectedRecordID = id

        DispatchQueue.main.async {
            isProgrammaticSelectionChange = false
        }
    }

    private static let detailDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private var recordCountSummary: String {
        if hasSearchQuery {
            return "\(visibleRecords.count) of \(store.records.count) records"
        }

        return "\(visibleRecords.count) \(visibleRecords.count == 1 ? "record" : "records")"
    }

    private var emptyStateTitle: String {
        if hasSearchQuery {
            return "No matching entries"
        }

        return "No clipboard history yet"
    }

    private var emptyStateDescription: String {
        if hasSearchQuery {
            return "Try a different search term."
        }

        return "Copy text in any app to start building history."
    }
}

private struct ClipboardHistoryRow: View {
    let record: ClipboardHistoryRecord
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(previewText)
                    .font(.body)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Text(Self.timestampFormatter.string(from: record.capturedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(record.size) B")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete record")
        }
        .padding(.vertical, 3)
    }

    private var previewText: String {
        let normalized = record.text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .newlines)

        let limit = 100
        guard normalized.count > limit else {
            return normalized
        }

        let index = normalized.index(normalized.startIndex, offsetBy: limit)
        return String(normalized[..<index]) + "..."
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
