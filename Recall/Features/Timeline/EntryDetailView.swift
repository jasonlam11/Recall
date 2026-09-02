import SwiftUI

/// Full view of a single entry: what was written, and what the model made of it.
///
/// The raw text is always primary. Derived metadata sits below it and is clearly
/// secondary — the writer's own words are the record, the model's reading of
/// them is commentary.
struct EntryDetailView: View {
    let entry: JournalEntry
    @State private var model: EntryDetailViewModel

    init(entry: JournalEntry, store: JournalStore, enricher: EntryEnricher) {
        self.entry = entry
        _model = State(initialValue: EntryDetailViewModel(entry: entry, store: store, enricher: enricher))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if model.isEditing { editor } else { body(of: entry) }
                Divider()
                analysis
                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(28)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.insight?.title ?? "Untitled")
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text(entry.createdAt, format: .dateTime.weekday(.wide).month().day().hour().minute())
                if let mood = entry.insight?.mood {
                    Label(mood.rawValue.capitalized, systemImage: mood.symbolName)
                }
                Spacer()
                actions
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if model.isEditing {
            Button("Cancel") { model.cancelEditing() }
                .buttonStyle(.bordered)
            Button("Save") { Task { await model.saveEdits() } }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSave)
        } else {
            Button("Edit", systemImage: "pencil") { model.beginEditing() }
                .buttonStyle(.bordered)
                .disabled(model.isAnalyzing)
            Button("Re-analyze", systemImage: "arrow.clockwise") {
                Task { await model.reanalyze() }
            }
            .buttonStyle(.bordered)
            .disabled(!model.canReanalyze)
            .help("Run the analysis again with the current prompts")
        }
    }

    // MARK: - Body

    @ViewBuilder
    private func body(of entry: JournalEntry) -> some View {
        Text(entry.text)
            .font(.body)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $model.draft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
                .frame(minHeight: 200)
            Text("Saving re-runs the analysis, since the summary, tags, and search index all describe the old text.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Analysis

    @ViewBuilder
    private var analysis: some View {
        if model.isAnalyzing {
            analyzing
        } else if let insight = entry.insight {
            VStack(alignment: .leading, spacing: 16) {
                section("Summary") {
                    Text(insight.summary).fixedSize(horizontal: false, vertical: true)
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
            Label("Not analyzed", systemImage: "circle.dashed")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// Shows the same streaming fill as the composer, so re-analysis reads as
    /// work happening rather than a frozen pane.
    @ViewBuilder
    private var analyzing: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(model.partial?.title ?? "Analyzing…")
                    .font(.headline)
                    .contentTransition(.opacity)
            }
            if let summary = model.partial?.summary {
                Text(summary)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let topics = model.partial?.topics, !topics.isEmpty {
                chips(topics, symbol: "tag")
            }
        }
        .animation(.snappy, value: model.partial?.title)
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
