import SwiftData
import SwiftUI

struct AskView: View {
    let store: JournalStore
    @Bindable var conversation: AskConversation
    /// Selecting a citation opens that entry in the detail pane.
    var onSelectEntry: (PersistentIdentifier) -> Void

    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.wide) {
                    if conversation.messages.isEmpty { emptyState }
                    ForEach(conversation.messages) { message in
                        bubble(message)
                    }
                    if let error = conversation.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
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
            composer
        }
        .background(Theme.paper)
        .animation(.smooth(duration: 0.3), value: conversation.messages.count)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            Text("Ask your journal")
                .font(Theme.Font.display)
                .foregroundStyle(Theme.ink)
            Text("Answered only from your own entries, on this device.")
                .font(Theme.Font.label)
                .foregroundStyle(Theme.inkSecondary)

            VStack(alignment: .leading, spacing: Theme.Space.tight) {
                ForEach(["Why have I been anxious lately?",
                         "What keeps coming up about work?",
                         "What did I say I'd follow up on?"], id: \.self) { example in
                    Button {
                        draft = example
                    } label: {
                        HStack(spacing: Theme.Space.tight) {
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                            Text(example)
                                .font(Theme.Font.entry)
                        }
                        .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, Theme.Space.tight)
        }
    }

    @ViewBuilder
    private func bubble(_ message: AskConversation.Message) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            SectionLabel(text: message.role == .user ? "You" : "Recall")
                .accessibilityHidden(true)

            if message.text.isEmpty && conversation.isResponding {
                HStack(spacing: Theme.Space.tight) {
                    ProgressView().controlSize(.small)
                    Text("Searching your entries…")
                        .font(Theme.Font.label)
                        .foregroundStyle(Theme.inkFaint)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text(message.text)
                    .font(message.role == .user ? Theme.Font.entryLarge : Theme.Font.entry)
                    .foregroundStyle(message.role == .user ? Theme.ink : Theme.inkSecondary)
                    .lineSpacing(Theme.proseLineSpacing)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    // The speaker is a visual caption above the text; folding it
                    // into the label keeps VoiceOver from losing track of who
                    // said what.
                    .accessibilityLabel("\(message.role == .user ? "You asked" : "Recall answered"): \(message.text)")
            }

            if !message.citations.isEmpty {
                citations(message.citations)
            }
        }
    }

    /// Citations are controls, not decoration. The point of citing is that the
    /// reader can check the model's work.
    @ViewBuilder
    private func citations(_ ids: [Int]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.hair) {
            SectionLabel(text: "From these entries")
            FlowRow(spacing: Theme.Space.hair) {
                ForEach(ids, id: \.self) { id in
                    if let entry = entry(for: id) {
                        Button {
                            onSelectEntry(entry.id)
                        } label: {
                            Chip(text: entry.insight?.title ?? "Untitled",
                                 symbol: "text.quote",
                                 tint: Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open source entry: \(entry.insight?.title ?? "Untitled")")
                    } else {
                        // The model cited an id that doesn't resolve. Shown
                        // rather than hidden, since it means it invented one.
                        Chip(text: "unknown entry", symbol: "questionmark.circle")
                    }
                }
            }
        }
        .padding(.top, Theme.Space.hair)
    }

    private func entry(for citation: Int) -> JournalEntry? {
        guard let id = Citation.entryID(for: citation) else { return nil }
        return store.entries.first { $0.id == id }
    }

    // MARK: - Composer

    /// The context window made visible.
    ///
    /// A 4096-token budget is a hard limit the user cannot see and did not agree
    /// to. Showing what's left turns "this conversation got too long" from a
    /// failure into a decision made in advance.
    @ViewBuilder
    private var budgetBar: some View {
        let budget = conversation.budget
        if budget.turns > 0 {
            HStack(spacing: Theme.Space.tight) {
                ProgressView(value: min(budget.fraction, 1))
                    .progressViewStyle(.linear)
                    .frame(width: 80)
                    .tint(budget.isRunningLow ? Theme.accent : Theme.inkFaint)

                if budget.exchangesRemaining <= 0 {
                    Text("Conversation is full")
                        .foregroundStyle(Theme.accent)
                    Button("Start a new one") { conversation.reset() }
                        .buttonStyle(.link)
                } else {
                    Text("about \(budget.exchangesRemaining) exchange\(budget.exchangesRemaining == 1 ? "" : "s") left")
                        .foregroundStyle(budget.isRunningLow ? Theme.accent : Theme.inkFaint)
                    if budget.isRunningLow {
                        Button("New conversation") { conversation.reset() }
                            .buttonStyle(.link)
                    }
                }
                Spacer()
            }
            .font(Theme.Font.meta)
            .padding(.horizontal, Theme.Space.normal)
            .padding(.top, Theme.Space.tight)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("About \(budget.exchangesRemaining) exchanges left in this conversation")
        }
    }

    @ViewBuilder
    private var composer: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.rule)
            budgetBar
            HStack(alignment: .bottom, spacing: Theme.Space.tight) {
                TextField("Ask about your entries", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.entry)
                    .lineLimit(1...5)
                    .onSubmit(send)
                Button("Ask", systemImage: "arrow.up.circle.fill", action: send)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.title2)
                    .foregroundStyle(canSend ? Theme.accent : Theme.inkFaint)
                    .accessibilityLabel("Send question")
                    .disabled(!canSend)
            }
            .padding(.horizontal, Theme.Space.normal)
            .padding(.vertical, Theme.Space.snug)
        }
        .background(Theme.surface)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespaces).isEmpty && conversation.canSend
    }

    private func send() {
        let question = draft
        guard !question.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        draft = ""
        Task { await conversation.ask(question) }
    }
}
