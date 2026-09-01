import SwiftUI

struct ContentView: View {
    let store: JournalStore
    let intelligence: any IntelligenceService

    var body: some View {
        NavigationSplitView {
            TimelineView(store: store)
                .navigationTitle("Recall")
                .frame(minWidth: 280)
        } detail: {
            CaptureView(store: store, intelligence: intelligence)
        }
    }
}
