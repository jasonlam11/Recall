import SwiftUI

@main
struct RecallApp: App {

    /// Composition root: the only place concrete types are chosen. Everything
    /// downstream receives what it needs, which is what makes the layers
    /// testable in isolation.
    private let store: JournalStore
    private let intelligence: any IntelligenceService
    private let retrieval: RetrievalService
    private let indexer: Indexer
    private let conversation: AskConversation
    private let audit: ToolAudit

    init() {
        do {
            store = try JournalStore()
        } catch {
            fatalError("Could not open the journal store: \(error)")
        }
        intelligence = OnDeviceIntelligenceService()
        let embeddings = EmbeddingService()
        retrieval = RetrievalService(embeddings: embeddings)
        indexer = Indexer(store: store, embeddings: embeddings)

        // The model reaches the journal only through tools, and tools only
        // through the retrieval layer. Wiring that here keeps the dependency
        // direction visible in one place.
        let audit = ToolAudit()
        self.audit = audit
        conversation = AskConversation(
            tools: [
                SearchJournalTool(store: store, retrieval: retrieval, audit: audit),
                OpenLoopsTool(store: store, audit: audit),
            ],
            audit: audit
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                store: store,
                intelligence: intelligence,
                retrieval: retrieval,
                indexer: indexer,
                conversation: conversation
            )
        }
        .defaultSize(width: 1040, height: 760)
        .windowResizability(.contentMinSize)
    }
}
