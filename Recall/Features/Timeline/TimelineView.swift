import SwiftData
import SwiftUI

/// Reads through `JournalStore` rather than `@Query` on purpose: the store is the
/// only type that touches SwiftData, and that boundary is what keeps the
/// intelligence layer storage-agnostic.
struct TimelineView: View {
    let store: JournalStore
    @Binding var selection: PersistentIdentifier?
    @Bindable var search: SearchViewModel

    private var entries: [JournalEntry] { store.entries }

    var body: some View {
        List(selection: $selection) {
            if search.isActive {
                Section(sectionTitle) {
                    ForEach(search.results) { result in
                        row(result.entry, reasons: result.reasons)
                            .tag(result.entry.id)
                    }
                }
            } else {
                ForEach(entries) { entry in
                    row(entry)
                        .tag(entry.id)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                if selection == entry.id { selection = nil }
                                try? store.delete(entry)
                            }
                        }
                }
            }
        }
        .searchable(text: $search.text, prompt: "Search by meaning")
        .onChange(of: search.text) { _, _ in search.queryChanged() }
        .overlay {
            if search.isActive && search.results.isEmpty && !search.isSearching {
                ContentUnavailableView.search(text: search.text)
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "No entries yet",
                    systemImage: "book.closed",
                    description: Text("Write your first entry and it'll be analyzed on this device.")
                )
            }
        }
        .refreshable { store.refresh() }
    }

    private var sectionTitle: String {
        if search.isSearching { return "Searching…" }
        return "\(search.results.count) match\(search.results.count == 1 ? "" : "es")"
    }

    @ViewBuilder
    private func row(_ entry: JournalEntry, reasons: [String] = []) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.insight?.title ?? "Untitled")
                    .font(.headline)
                Spacer()
                Text(entry.createdAt, format: .dateTime.month().day())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(entry.insight?.summary ?? entry.text)
                .font(.callout).foregroundStyle(.secondary).lineLimit(2)
            if let insight = entry.insight {
                HStack(spacing: 6) {
                    Label(insight.mood.rawValue.capitalized, systemImage: insight.mood.symbolName)
                    ForEach(insight.topics.prefix(2), id: \.self) { Text("· \($0)") }
                }
                .font(.caption2).foregroundStyle(.tertiary)
            }
            // Why this entry matched, so ranking isn't a black box.
            if !reasons.isEmpty {
                Text(reasons.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 4)
    }
}
