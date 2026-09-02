import Foundation
import Observation

/// Editing and re-analysis for a single entry.
///
/// Both operations end the same way: derived data is discarded, then
/// regenerated. The difference is only whether the writing changed.
@MainActor
@Observable
final class EntryDetailViewModel {

    private(set) var isEditing = false
    private(set) var isAnalyzing = false
    private(set) var partial: EntryInsight.PartiallyGenerated?
    private(set) var errorMessage: String?
    var draft: String = ""

    private let entry: JournalEntry
    private let store: JournalStore
    private let enricher: EntryEnricher

    init(entry: JournalEntry, store: JournalStore, enricher: EntryEnricher) {
        self.entry = entry
        self.store = store
        self.enricher = enricher
    }

    var canReanalyze: Bool { !isAnalyzing && !isEditing && enricher.availability.isReady }
    var hasChanges: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
            != entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var canSave: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAnalyzing
    }

    func beginEditing() {
        draft = entry.text
        errorMessage = nil
        isEditing = true
    }

    func cancelEditing() {
        isEditing = false
        draft = ""
        errorMessage = nil
    }

    /// Saves edited text, then regenerates everything derived from it.
    ///
    /// The text is committed first and separately. If analysis then fails the
    /// edit still stands — the entry is simply unanalyzed, which the detail view
    /// shows honestly rather than leaving stale metadata describing text that no
    /// longer exists.
    func saveEdits() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        guard hasChanges else { cancelEditing(); return }

        errorMessage = nil
        do {
            try store.update(entry, text: text)
        } catch {
            errorMessage = "Couldn't save your changes: \(error.localizedDescription)"
            return
        }
        isEditing = false
        draft = ""
        await analyze()
    }

    /// Re-runs enrichment without changing the writing.
    ///
    /// Useful when the prompt has improved since the entry was written — early
    /// entries were tagged with the writer themselves and with pronouns as
    /// people, before those instructions were fixed.
    func reanalyze() async {
        errorMessage = nil
        do {
            try store.clearDerivedData(for: entry)
        } catch {
            errorMessage = "Couldn't clear the old analysis: \(error.localizedDescription)"
            return
        }
        await analyze()
    }

    private func analyze() async {
        isAnalyzing = true
        partial = nil
        defer { isAnalyzing = false; partial = nil }

        do {
            try await enricher.enrich(entry) { partial = $0 }
        } catch let error as IntelligenceError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
