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

    private var selectedEntry: JournalEntry? {
        guard let selection else { return nil }
        return store.entries.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            TimelineView(store: store, selection: $selection, search: search)
                .navigationTitle("Recall")
                .frame(minWidth: 300)
                .toolbar {
                    Button("Ask", systemImage: "bubble.left.and.text.bubble.right") {
                        isAsking = true
                        selection = nil
                    }
                    .disabled(isAsking)

                    Button("New Entry", systemImage: "square.and.pencil") {
                        isAsking = false
                        selection = nil
                    }
                    .disabled(!isAsking && selection == nil)

                    // The transcript lives in the session and the context
                    // window is 4096 tokens, so a long conversation has to be
                    // discardable rather than silently trimmed.
                    Button("New Conversation", systemImage: "arrow.counterclockwise") {
                        conversation.reset()
                        isAsking = true
                        selection = nil
                    }
                    .disabled(conversation.messages.isEmpty)
                }
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
