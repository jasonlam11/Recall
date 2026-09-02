import Foundation
import Observation

/// Drives the capture screen.
///
/// The order of operations matters: the entry is persisted *first*, then
/// enrichment streams in. A writer never loses text because a model call failed.
@MainActor
@Observable
final class CaptureViewModel {

    var text: String = ""
    private(set) var partial: EntryInsight.PartiallyGenerated?
    private(set) var isEnriching = false
    private(set) var errorMessage: String?

    private let store: JournalStore
    private let intelligence: any IntelligenceService
    private let indexer: Indexer
    private let enricher: EntryEnricher

    init(store: JournalStore, intelligence: any IntelligenceService, indexer: Indexer) {
        self.store = store
        self.intelligence = intelligence
        self.indexer = indexer
        self.enricher = EntryEnricher(store: store, intelligence: intelligence, indexer: indexer)
    }

    var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isEnriching }
    var availability: ModelAvailability { intelligence.availability }

    func save() async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }

        errorMessage = nil
        partial = nil

        // 1. Persist immediately. This must not depend on the model.
        let entry: JournalEntry
        do {
            entry = try store.create(text: body)
        } catch {
            errorMessage = "Couldn't save this entry: \(error.localizedDescription)"
            return
        }

        text = ""

        // 2. Index on the raw text right away, so the entry is searchable even
        //    if enrichment fails. It's re-indexed below once the insight lands.
        await indexer.index(entry)

        // 3. Enrich. Failure here leaves a valid, unenriched entry.
        guard availability.isReady else { return }
        isEnriching = true
        defer { isEnriching = false }

        // 4. Enrich, persist, and re-index. A failure here leaves a valid,
        //    unenriched entry. The writing is already safe.
        do {
            try await enricher.enrich(entry) { partial = $0 }
        } catch let error as IntelligenceError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
