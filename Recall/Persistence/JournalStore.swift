import Foundation
import Observation
import SwiftData

/// The only type in the app that talks to SwiftData.
///
/// Keeping persistence behind this boundary is what lets the intelligence layer
/// stay ignorant of storage: tools call retrieval, retrieval calls the store,
/// and no `@Model` type ever reaches a prompt or a `Tool`.
@MainActor
@Observable
final class JournalStore {
    /// Current entries, newest first. Views read this instead of re-fetching,
              /// so any mutation below propagates through Observation automatically.
    private(set) var entries: [JournalEntry] = []

    @ObservationIgnored let container: ModelContainer
    @ObservationIgnored private var context: ModelContext { container.mainContext }

    init(inMemory: Bool = false) throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        self.container = try ModelContainer(for: JournalEntry.self, configurations: config)
        refresh()
    }

    /// Single point where the cached list is rebuilt. Every mutation calls this,
    /// which is why views never need to know a write happened.
    func refresh() {
        entries = (try? allEntries()) ?? []
    }

    // MARK: - Writes

    @discardableResult
    func create(text: String) throws -> JournalEntry {
        let entry = JournalEntry(text: text)
        context.insert(entry)
        try context.save()
        refresh()
        return entry
    }

    /// Replaces an entry's text and discards everything derived from it.
    ///
    /// Clearing `insight` and `embedding` is the point, not housekeeping. Stale
    /// derived data makes search silently lie: an entry edited to be about a
    /// thesis would still surface for "gym", because the old topics and vector
    /// still describe text that no longer exists. Better to show an entry as
    /// unanalyzed than to describe it wrongly.
    func update(_ entry: JournalEntry, text: String) throws {
        entry.text = text
        entry.insight = nil
        entry.embedding = nil
        try context.save()
        refresh()
    }

    /// Discards derived data without touching the writing, for re-analysis.
    func clearDerivedData(for entry: JournalEntry) throws {
        entry.insight = nil
        entry.embedding = nil
        try context.save()
        refresh()
    }

    func attach(_ insight: EntryInsight, to entry: JournalEntry) throws {
        entry.insight = insight
        try context.save()
        refresh()
    }

    func attach(embedding: [Float], to entry: JournalEntry) throws {
        entry.embedding = embedding
        try context.save()
        refresh()
    }

    func delete(_ entry: JournalEntry) throws {
        context.delete(entry)
        try context.save()
        refresh()
    }

    // MARK: - Reads

    func allEntries() throws -> [JournalEntry] {
        try context.fetch(
            FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        )
    }

    /// Entries that still need an embedding — the backlog the indexer works through.
    func unindexedEntries() throws -> [JournalEntry] {
        try allEntries().filter { !$0.isIndexed }
    }

    func entries(in range: ClosedRange<Date>) throws -> [JournalEntry] {
        let lower = range.lowerBound, upper = range.upperBound
        return try context.fetch(
            FetchDescriptor<JournalEntry>(
                predicate: #Predicate { $0.createdAt >= lower && $0.createdAt <= upper },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )
    }
}
