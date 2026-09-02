import SwiftUI

/// Full view of a single entry: what was written, and what the model made of it.
///
/// The writing is primary and set in serif; derived metadata sits below a rule
/// in interface type. The distinction is the point: the writer's words are the
/// record, the model's reading is commentary.
struct EntryDetailView: View {
    let entry: JournalEntry
    @State private var model: EntryDetailViewModel

    init(entry: JournalEntry, store: JournalStore, enricher: EntryEnricher) {
        self.entry = entry
        _model = State(initialValue: EntryDetailViewModel(entry: entry, store: store, enricher: enricher))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.loose) {
                header
                if model.isEditing { editor } else { writing }
                Divider().overlay(Theme.rule)
                analysis
                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(Theme.Font.meta)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: Theme.readingWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Space.wide)
            .padding(.vertical, Theme.Space.page)
        }
        .background(Theme.paper)
        .animation(.smooth(duration: 0.3), value: model.isEditing)
        .animation(.smooth(duration: 0.3), value: model.isAnalyzing)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            HStack(alignment: .top) {
                Text(entry.insight?.title ?? "Untitled")
                    .font(Theme.Font.display)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Space.normal)
                HStack(spacing: Theme.Space.tight) { actions }
            }
            HStack(spacing: Theme.Space.tight) {
                Text(entry.createdAt, format: .dateTime.weekday(.wide).month(.wide).day().hour().minute())
                if let mood = entry.insight?.mood {
                    Chip(text: mood.rawValue.capitalized, symbol: mood.symbolName, tint: mood.tint)
                }
            }
            .font(Theme.Font.meta)
            .foregroundStyle(Theme.inkFaint)
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
                .labelStyle(.iconOnly)
                .help("Edit this entry")
                .disabled(model.isAnalyzing)
            Button("Re-analyze", systemImage: "arrow.clockwise") {
                Task { await model.reanalyze() }
            }
            .buttonStyle(.bordered)
            .labelStyle(.iconOnly)
            .help("Run the analysis again with the current prompts")
            .disabled(!model.canReanalyze)
        }
    }

    // MARK: - Writing

    @ViewBuilder
    private var writing: some View {
        Text(entry.text)
            .font(Theme.Font.entryLarge)
            .foregroundStyle(Theme.ink)
            .lineSpacing(Theme.proseLineSpacing)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var editor: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            TextEditor(text: $model.draft)
                .font(Theme.Font.entryLarge)
                .foregroundStyle(Theme.ink)
                .lineSpacing(Theme.proseLineSpacing)
                .scrollContentBackground(.hidden)
                .padding(Theme.Space.snug)
                .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
                .frame(minHeight: 240)
                .accessibilityLabel("Entry text")
            Text("Saving re-runs the analysis — the summary, tags, and search index all describe the old text.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkFaint)
        }
    }

    // MARK: - Analysis

    @ViewBuilder
    private var analysis: some View {
        if model.isAnalyzing {
            analyzing
        } else if let insight = entry.insight {
            VStack(alignment: .leading, spacing: Theme.Space.loose) {
                section("Summary") {
                    Text(insight.summary)
                        .font(Theme.Font.entry)
                        .lineSpacing(Theme.proseLineSpacing - 2)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !insight.people.isEmpty || !insight.topics.isEmpty {
                    section("Mentions") {
                        FlowRow(spacing: Theme.Space.hair) {
                            ForEach(insight.people, id: \.self) { Chip(text: $0, symbol: "person") }
                            ForEach(insight.topics, id: \.self) { Chip(text: $0, symbol: "tag") }
                        }
                    }
                }
                if !insight.openLoops.isEmpty {
                    section("Still open") {
                        VStack(alignment: .leading, spacing: Theme.Space.hair) {
                            ForEach(insight.openLoops, id: \.self) { loop in
                                Label(loop, systemImage: "arrow.turn.down.right")
                                    .font(Theme.Font.label)
                                    .foregroundStyle(Theme.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        } else {
            Label("Not analyzed", systemImage: "circle.dashed")
                .font(Theme.Font.label)
                .foregroundStyle(Theme.inkFaint)
        }
    }

    /// Shows the same streaming fill as the composer, so re-analysis reads as
    /// work happening rather than a frozen pane.
    @ViewBuilder
    private var analyzing: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            HStack(spacing: Theme.Space.tight) {
                ProgressView().controlSize(.small)
                Text(model.partial?.title ?? "Analyzing…")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.opacity)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Analyzing entry")

            if let summary = model.partial?.summary {
                Text(summary)
                    .font(Theme.Font.entry)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let topics = model.partial?.topics, !topics.isEmpty {
                FlowRow(spacing: Theme.Space.hair) {
                    ForEach(topics, id: \.self) { Chip(text: $0, symbol: "tag") }
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: model.partial?.title)
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            SectionLabel(text: title)
            content()
        }
    }
}
