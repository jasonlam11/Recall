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
                VStack(alignment: .leading, spacing: 18) {
                    if conversation.messages.isEmpty { emptyState }
                    ForEach(conversation.messages) { message in
                        bubble(message)
                    }
                    if let error = conversation.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(24)
            }
            Divider()
            composer
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask your journal").font(.largeTitle.bold())
            Text("Questions are answered only from your own entries, on this device.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(["Why have I been anxious lately?",
                         "What keeps coming up about work?",
                         "What did I say I'd follow up on?"], id: \.self) { example in
                    Button(example) { draft = example }
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func bubble(_ message: AskConversation.Message) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message.role == .user ? "You" : "Recall")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            if message.text.isEmpty && conversation.isResponding {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Searching your entries…").font(.callout).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text(message.text)
                    .font(.body)
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

    /// Citations are rendered as controls, not decoration — the point of citing
    /// is that the user can check the model's work.
    @ViewBuilder
    private func citations(_ ids: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sources").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(ids, id: \.self) { id in
                if let entry = entry(for: id) {
                    Button {
                        onSelectEntry(entry.id)
                    } label: {
                        Label("[\(id)] \(entry.insight?.title ?? "Untitled")", systemImage: "text.quote")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                    .accessibilityLabel("Open source entry: \(entry.insight?.title ?? "Untitled")")
                } else {
                    // The model cited an id that doesn't resolve — worth showing
                    // rather than hiding, since it means it invented one.
                    Label("[\(id)] unknown entry", systemImage: "questionmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func entry(for citation: Int) -> JournalEntry? {
        guard let id = Citation.entryID(for: citation) else { return nil }
        return store.entries.first { $0.id == id }
    }

    /// The context window made visible.
    ///
    /// A 4096-token budget is a hard limit the user cannot see and did not
    /// agree to. Showing what's left turns "this conversation got too long"
    /// from a failure into a decision they get to make in advance.
    @ViewBuilder
    private var budgetBar: some View {
        let budget = conversation.budget
        if budget.turns > 0 {
            HStack(spacing: 8) {
                ProgressView(value: min(budget.fraction, 1))
                    .progressViewStyle(.linear)
                    .frame(width: 90)
                    .tint(budget.isRunningLow ? .orange : .secondary)

                if budget.exchangesRemaining <= 0 {
                    Text("Conversation is full")
                        .foregroundStyle(.orange)
                    Button("Start a new one") { conversation.reset() }
                        .buttonStyle(.link)
                } else {
                    Text("about \(budget.exchangesRemaining) exchange\(budget.exchangesRemaining == 1 ? "" : "s") left")
                        .foregroundStyle(budget.isRunningLow ? .orange : .secondary)
                    if budget.isRunningLow {
                        Button("New conversation") { conversation.reset() }
                            .buttonStyle(.link)
                    }
                }
                Spacer()
            }
            .font(.caption)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("About \(budget.exchangesRemaining) exchanges left in this conversation")
        }
    }

    @ViewBuilder
    private var composer: some View {
        VStack(spacing: 0) {
        budgetBar
        HStack(spacing: 8) {
            TextField("Ask about your entries", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .onSubmit(send)
            Button("Ask", systemImage: "arrow.up.circle.fill", action: send)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.title2)
                .accessibilityLabel("Send question")
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || !conversation.canSend)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        }
        .background(.quaternary.opacity(0.3))
    }

    private func send() {
        let question = draft
        guard !question.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        draft = ""
        Task { await conversation.ask(question) }
    }
}
