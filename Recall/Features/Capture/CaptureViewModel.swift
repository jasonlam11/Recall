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

    init(store: JournalStore, intelligence: any IntelligenceService, indexer: Indexer) {
        self.store = store
        self.intelligence = intelligence
        self.indexer = indexer
    }

    var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isEnriching }
    var availability: ModelAvailability { intelligence.availability }

    /// Called as the writer types, so the model is warm by the time they save.
    func prewarmIfNeeded() {
        (intelligence as? OnDeviceIntelligenceService)?.prewarm()
    }

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

        var last: EntryInsight.PartiallyGenerated?
        do {
            for try await snapshot in intelligence.enrichStream(entryText: body) {
                partial = snapshot
                last = snapshot
            }
        } catch let error as IntelligenceError {
            errorMessage = error.errorDescription
            return
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // 4. Only persist metadata once it's actually complete.
        guard let last, let insight = EntryInsight(completed: last) else {
            errorMessage = "The analysis came back incomplete. Your entry is saved."
            return
        }
        do {
            try store.attach(insight, to: entry)
        } catch {
            errorMessage = "Saved the entry, but couldn't save its analysis."
            return
        }

        // 5. Re-index now that the summary and topics exist — they carry more
        //    signal than raw prose alone.
        await indexer.reindex(entry)
    }
}
