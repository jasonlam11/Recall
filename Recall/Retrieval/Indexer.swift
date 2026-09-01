import Foundation

/// Keeps embeddings in sync with entries.
///
/// Runs as a backlog worker rather than inline with saving: an entry is useful
/// the moment it's written, and indexing is a background concern. This also
/// backfills entries written before the embedding layer existed.
@MainActor
final class Indexer {

    private let store: JournalStore
    private let embeddings: EmbeddingService

    init(store: JournalStore, embeddings: EmbeddingService) {
        self.store = store
        self.embeddings = embeddings
    }

    /// The text actually embedded for an entry.
    ///
    /// Includes the model's summary and topics alongside the raw text, because
    /// enrichment has already distilled the entry — throwing that away and
    /// embedding only raw prose would discard work the model already did.
    private func indexText(for entry: JournalEntry) -> String {
        var parts = [entry.text]
        if let insight = entry.insight {
            parts.append(insight.summary)
            parts.append(insight.topics.joined(separator: ", "))
            parts.append(insight.people.joined(separator: ", "))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    func index(_ entry: JournalEntry) async {
        guard let vector = try? await embeddings.vector(for: indexText(for: entry)) else { return }
        try? store.attach(embedding: vector, to: entry)
    }

    /// Works through everything that has no embedding yet.
    func indexBacklog() async {
        let pending = (try? store.unindexedEntries()) ?? []
        for entry in pending {
            await index(entry)
        }
    }

    /// Re-embeds an entry whose insight arrived after it was first indexed.
    func reindex(_ entry: JournalEntry) async {
        await index(entry)
    }
}
