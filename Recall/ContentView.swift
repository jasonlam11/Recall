import SwiftData
import SwiftUI

struct ContentView: View {
    let store: JournalStore
    let intelligence: any IntelligenceService
    let indexer: Indexer

    @State private var selection: PersistentIdentifier?
    @State private var search: SearchViewModel

    init(store: JournalStore, intelligence: any IntelligenceService, retrieval: RetrievalService, indexer: Indexer) {
        self.store = store
        self.intelligence = intelligence
        self.indexer = indexer
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
                    Button("New Entry", systemImage: "square.and.pencil") {
                        selection = nil
                    }
                    .disabled(selection == nil)
                }
        } detail: {
            // No selection means "compose". Selecting an entry replaces the
            // editor with that entry — one column, two modes, no tab bar.
            if let selectedEntry {
                EntryDetailView(entry: selectedEntry)
            } else {
                CaptureView(store: store, intelligence: intelligence, indexer: indexer)
            }
        }
        // Backfills entries written before embeddings existed, and any whose
        // indexing was interrupted.
        .task { await indexer.indexBacklog() }
    }
}
