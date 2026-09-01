import SwiftUI

struct CaptureView: View {
    @State private var model: CaptureViewModel

    init(store: JournalStore, intelligence: any IntelligenceService) {
        _model = State(initialValue: CaptureViewModel(store: store, intelligence: intelligence))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            TextEditor(text: $model.text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
                .frame(minHeight: 180)
                .onChange(of: model.text) { _, new in
                    if new.count == 1 { model.prewarmIfNeeded() }
                }

            HStack {
                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.isEnriching ? "Analyzing…" : "Save Entry") {
                    Task { await model.save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSave)
            }

            if let partial = model.partial {
                InsightCard(partial: partial, isStreaming: model.isEnriching)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer()
        }
        .padding(24)
        .animation(.snappy, value: model.partial?.title)
        .animation(.snappy, value: model.isEnriching)
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("New Entry").font(.largeTitle.bold())
            if let explanation = model.availability.explanation {
                Text(explanation).font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Analyzed privately on this device.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// Renders a partially generated insight.
///
/// Every field is optional because generation is still in flight — fields appear
/// in the order they're declared on `EntryInsight`, which is why `title` and
/// `summary` come first.
private struct InsightCard: View {
    let partial: EntryInsight.PartiallyGenerated
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(partial.title ?? "…")
                    .font(.headline)
                    .contentTransition(.opacity)
                Spacer()
                if let mood = partial.mood {
                    Label(mood.rawValue.capitalized, systemImage: mood.symbolName)
                        .font(.caption)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                }
                if isStreaming { ProgressView().controlSize(.small) }
            }

            if let summary = partial.summary {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }

            if let people = partial.people, !people.isEmpty {
                TagRow(label: "People", items: people, symbol: "person")
            }
            if let topics = partial.topics, !topics.isEmpty {
                TagRow(label: "Topics", items: topics, symbol: "tag")
            }
            if let loops = partial.openLoops, !loops.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Open loops").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(loops, id: \.self) { loop in
                        Label(loop, systemImage: "arrow.turn.down.right")
                            .font(.caption)
                    }
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 12))
    }
}

private struct TagRow: View {
    let label: String
    let items: [String]
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
            // Explicit ids: streamed arrays grow, and index-based identity makes
            // SwiftUI recycle views incorrectly mid-stream.
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
}
