import SwiftUI

/// Full view of a single entry: what was written, and what the model made of it.
///
/// The raw text is always shown and always primary. Derived metadata sits below
/// it and is clearly secondary — the writer's own words are the record, the
/// model's reading of them is commentary.
struct EntryDetailView: View {
    let entry: JournalEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.insight?.title ?? "Untitled")
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Text(entry.createdAt, format: .dateTime.weekday(.wide).month().day().hour().minute())
                        if let mood = entry.insight?.mood {
                            Label(mood.rawValue.capitalized, systemImage: mood.symbolName)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Text(entry.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if let insight = entry.insight {
                    Divider()
                    VStack(alignment: .leading, spacing: 16) {
                        section("Summary") {
                            Text(insight.summary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !insight.people.isEmpty {
                            section("People") { chips(insight.people, symbol: "person") }
                        }
                        if !insight.topics.isEmpty {
                            section("Topics") { chips(insight.topics, symbol: "tag") }
                        }
                        if !insight.openLoops.isEmpty {
                            section("Open loops") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(insight.openLoops, id: \.self) { loop in
                                        Label(loop, systemImage: "arrow.turn.down.right")
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    .font(.callout)
                } else {
                    Divider()
                    Label("Not analyzed", systemImage: "sparkles.slash")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(28)
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder
    private func chips(_ items: [String], symbol: String) -> some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: symbol)
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.quaternary.opacity(0.5), in: .capsule)
            }
        }
    }
}
