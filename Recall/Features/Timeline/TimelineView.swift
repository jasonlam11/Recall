import SwiftData
import SwiftUI

/// Reads through `JournalStore` rather than `@Query` on purpose: the store is the
/// only type that touches SwiftData, and that boundary is what keeps the
/// intelligence layer storage-agnostic.
struct TimelineView: View {
    let store: JournalStore
    @Binding var selection: PersistentIdentifier?

    private var entries: [JournalEntry] { store.entries }

    var body: some View {
        List(selection: $selection) {
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
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No entries yet",
                    systemImage: "book.closed",
                    description: Text("Write your first entry and it'll be analyzed on this device.")
                )
            }
        }
        .refreshable { store.refresh() }
    }

    @ViewBuilder
    private func row(_ entry: JournalEntry) -> some View {
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
        }
        .padding(.vertical, 4)
    }
}
