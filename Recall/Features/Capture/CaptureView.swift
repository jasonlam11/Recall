import SwiftUI

struct CaptureView: View {
    @State private var model: CaptureViewModel
    @FocusState private var isWriting: Bool

    init(store: JournalStore, intelligence: any IntelligenceService, indexer: Indexer) {
        _model = State(initialValue: CaptureViewModel(
            store: store, intelligence: intelligence, indexer: indexer
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.normal) {
                header
                editor
                footer
                if let partial = model.partial {
                    InsightCard(partial: partial, isStreaming: model.isEnriching)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 12)),
                            removal: .opacity
                        ))
                }
            }
            .frame(maxWidth: Theme.readingWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Space.wide)
            .padding(.vertical, Theme.Space.page)
        }
        .background(Theme.paper)
        .animation(.smooth(duration: 0.35), value: model.partial?.title)
        .animation(.smooth(duration: 0.35), value: model.isEnriching)
        .onAppear { isWriting = true }
    }

    /// The date, not a page title. A journal knows what day it is; it doesn't
    /// need to announce that you're about to write in it.
    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.hair) {
            Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(Theme.Font.title)
                .foregroundStyle(Theme.ink)
            Text(model.availability.explanation ?? "Analyzed privately on this device.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkFaint)
        }
    }

    /// No visible container. A bordered box reads as a form field; the text
    /// should look like it's sitting on the page.
    @ViewBuilder
    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if model.text.isEmpty {
                Text("What happened today?")
                    .font(Theme.Font.entryLarge)
                    .foregroundStyle(Theme.inkFaint)
                    .allowsHitTesting(false)
                    .padding(.top, 1)
            }
            TextEditor(text: $model.text)
                .font(Theme.Font.entryLarge)
                .foregroundStyle(Theme.ink)
                .lineSpacing(Theme.proseLineSpacing)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .focused($isWriting)
                // Capped, because a TextEditor inside a ScrollView expands to
                // fill whatever it's offered, which left ~450pt of dead space
                // between the placeholder and the Save button.
                .frame(minHeight: 160, maxHeight: 300)
                .accessibilityLabel("Journal entry")
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.snug) {
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !model.text.isEmpty {
                Text("\(model.text.split(separator: " ").count) words")
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer()
            Button(model.isEnriching ? "Analyzing…" : "Save Entry") {
                Task { await model.save() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canSave)
        }
    }
}

/// The insight as it's generated.
///
/// This is the moment that shows what the app does, so it's treated as the
/// payoff rather than as a status readout: fields fade in as they arrive, in
/// declaration order, and the mood carries the entry's colour.
private struct InsightCard: View {
    let partial: EntryInsight.PartiallyGenerated
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: isStreaming ? "Reading your entry" : "What I noticed")
                Spacer()
                if isStreaming {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Analyzing entry")
                }
            }

            if let title = partial.title {
                Text(title)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            if let summary = partial.summary {
                Text(summary)
                    .font(Theme.Font.entry)
                    .lineSpacing(Theme.proseLineSpacing - 2)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            let people = partial.people ?? []
            let topics = partial.topics ?? []
            if partial.mood != nil || !people.isEmpty || !topics.isEmpty {
                FlowRow(spacing: Theme.Space.hair) {
                    if let mood = partial.mood {
                        Chip(text: mood.rawValue.capitalized, symbol: mood.symbolName, tint: mood.tint)
                    }
                    ForEach(people, id: \.self) { Chip(text: $0, symbol: "person") }
                    ForEach(topics, id: \.self) { Chip(text: $0, symbol: "tag") }
                }
            }

            if let loops = partial.openLoops, !loops.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.hair) {
                    SectionLabel(text: "Still open")
                    ForEach(loops, id: \.self) { loop in
                        Label(loop, systemImage: "arrow.turn.down.right")
                            .font(Theme.Font.meta)
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(Theme.Space.normal)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
    }
}

/// Wraps chips onto multiple lines instead of overflowing a single row.
///
/// An `HStack` of chips clips as soon as the model returns five topics, which it
/// routinely does. This is the smallest correct fix.
struct FlowRow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
