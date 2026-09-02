import Foundation

/// Runs enrichment for one entry and persists the result.
///
/// Extracted from `CaptureViewModel` when editing arrived and needed the exact
/// same sequence — stream an insight, refuse to store a partial one, re-index
/// once the summary and topics exist. Duplicating that would have meant two
/// places to get the failure ordering wrong.
@MainActor
final class EntryEnricher {

    private let store: JournalStore
    private let intelligence: any IntelligenceService
    private let indexer: Indexer

    init(store: JournalStore, intelligence: any IntelligenceService, indexer: Indexer) {
        self.store = store
        self.intelligence = intelligence
        self.indexer = indexer
    }

    var availability: ModelAvailability { intelligence.availability }

    /// Enriches `entry`, reporting each snapshot so callers can render progress.
    ///
    /// Throws only when enrichment fails. The entry itself is never modified on
    /// failure, so a caller can surface the error and leave the writing intact.
    func enrich(
        _ entry: JournalEntry,
        onPartial: (EntryInsight.PartiallyGenerated) -> Void
    ) async throws {
        guard availability.isReady else {
            throw IntelligenceError.unavailable(availability)
        }

        var last: EntryInsight.PartiallyGenerated?
        for try await snapshot in intelligence.enrichStream(entryText: entry.text) {
            onPartial(snapshot)
            last = snapshot
        }

        guard let last, let insight = EntryInsight(completed: last) else {
            throw IntelligenceError.failed("The analysis came back incomplete.")
        }
        try store.attach(insight, to: entry)

        // Re-index now that summary, topics, and open loops exist — they carry
        // more signal than raw prose alone.
        await indexer.reindex(entry)
    }
}
