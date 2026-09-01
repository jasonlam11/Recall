import SwiftUI

/// Reads through `JournalStore` rather than `@Query` on purpose: the store is
/// the only type that touches SwiftData, and that boundary is what keeps the
/// intelligence layer storage-agnostic.
struct TimelineView: View {
    let store: JournalStore
    @State private var entries: [JournalEntry] = []

    var body: some View {
        List {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(entry.insight?.title ?? "Untitled")
                            .font(.headline)
                        Spacer()
                        Text(entry.createdAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(entry.insight?.summary ?? entry.text)
                        .font(.callout).foregroundStyle(.secondary).lineLimit(3)
                    if let insight = entry.insight {
                        HStack(spacing: 6) {
                            Label(insight.mood.rawValue.capitalized, systemImage: insight.mood.symbolName)
                            ForEach(insight.topics.prefix(3), id: \.self) { Text("· \($0)") }
                        }
                        .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
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
        .task { reload() }
        .refreshable { reload() }
    }

    private func reload() {
        entries = (try? store.allEntries()) ?? []
    }
}
