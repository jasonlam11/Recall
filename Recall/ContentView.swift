import SwiftData
import SwiftUI

struct ContentView: View {
    let store: JournalStore
    let intelligence: any IntelligenceService

    @State private var selection: PersistentIdentifier?

    private var selectedEntry: JournalEntry? {
        guard let selection else { return nil }
        return store.entries.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            TimelineView(store: store, selection: $selection)
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
                CaptureView(store: store, intelligence: intelligence)
            }
        }
    }
}
