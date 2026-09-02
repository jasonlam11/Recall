import SwiftData
import SwiftUI

struct ContentView: View {
    let store: JournalStore
    let intelligence: any IntelligenceService
    let indexer: Indexer
    let conversation: AskConversation

    @State private var selection: PersistentIdentifier?
    @State private var isAsking = false
    @State private var search: SearchViewModel

    init(
        store: JournalStore,
        intelligence: any IntelligenceService,
        retrieval: RetrievalService,
        indexer: Indexer,
        conversation: AskConversation
    ) {
        self.store = store
        self.intelligence = intelligence
        self.indexer = indexer
        self.conversation = conversation
        _search = State(initialValue: SearchViewModel(retrieval: retrieval, store: store))
    }

    /// The two things you can do, as visible controls rather than toolbar
    /// items. The toolbar versions were there and unfindable — the same problem
    /// `.searchable` had in this sidebar. A control the user can't locate is
    /// a feature that doesn't exist.
    @ViewBuilder
    private var modePicker: some View {
        HStack(spacing: 8) {
            Button {
                isAsking = false
                selection = nil
            } label: {
                Label("Write", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isWriting ? .accentColor : nil)

            Button {
                isAsking = true
                selection = nil
            } label: {
                Label("Ask", systemImage: "bubble.left.and.text.bubble.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isAsking ? .accentColor : nil)

            if isAsking && !conversation.messages.isEmpty {
                // The transcript lives in the session and the window is 4096
                // tokens, so a long conversation must be discardable.
                Button {
                    conversation.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .help("Start a new conversation")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }

    private var isWriting: Bool { !isAsking && selection == nil }

    private var selectedEntry: JournalEntry? {
        guard let selection else { return nil }
        return store.entries.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                modePicker
                Divider()
                TimelineView(store: store, selection: $selection, search: search)
            }
            .navigationTitle("Recall")
            .frame(minWidth: 300)
        } detail: {
            // Three modes in one column, driven by two pieces of state. Selecting
            // an entry always wins over asking, since it's the more specific
            // intent.
            if let selectedEntry {
                EntryDetailView(entry: selectedEntry)
            } else if isAsking {
                AskView(store: store, conversation: conversation) { id in
                    selection = id
                }
            } else {
                CaptureView(store: store, intelligence: intelligence, indexer: indexer)
            }
        }
        // Backfills entries written before embeddings existed, and any whose
        // indexing was interrupted.
        .task { await indexer.indexBacklog() }
    }
}
