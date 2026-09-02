import Foundation
import SwiftData

/// Adapts stored entries to the pure `Ranker` and back.
///
/// Everything interesting about ranking lives in `Ranker`. This type exists to
/// own the parts that can't be pure: hard filters against SwiftData, and the
/// async embedding of the query.
@MainActor
final class RetrievalService {

    struct Query {
        var text: String = ""
        var mood: Mood?
        var dateRange: ClosedRange<Date>?
        var limit: Int = 20
    }

    struct Result: Identifiable {
        let entry: JournalEntry
        let score: Float
        /// Why this entry matched, surfaced so ranking isn't a black box.
        let reasons: [String]
        var id: PersistentIdentifier { entry.id }
    }

    private let embeddings: EmbeddingService
    private let ranker: Ranker

    init(embeddings: EmbeddingService, ranker: Ranker = Ranker()) {
        self.embeddings = embeddings
        self.ranker = ranker
    }

    func search(_ query: Query, in allEntries: [JournalEntry]) async -> [Result] {
        // Hard filters first: they only shrink the candidate set, so they're
        // strictly cheaper than scoring.
        var entries = allEntries
        if let range = query.dateRange {
            entries = entries.filter { range.contains($0.createdAt) }
        }
        guard !entries.isEmpty, !query.text.isEmpty else { return [] }

        let byID = Dictionary(uniqueKeysWithValues: entries.map { (key(for: $0), $0) })
        let candidates = entries.map(candidate(from:))
        let queryEmbedding = try? await embeddings.vector(for: query.text)

        return ranker.rank(
            query: query.text,
            candidates: candidates,
            queryEmbedding: queryEmbedding,
            mood: query.mood,
            limit: query.limit
        ).compactMap { scored in
            guard let entry = byID[scored.candidate.id] else { return nil }
            return Result(entry: entry, score: scored.score, reasons: scored.reasons)
        }
    }

    private func key(for entry: JournalEntry) -> String {
        String(describing: entry.id)
    }

    private func candidate(from entry: JournalEntry) -> Ranker.Candidate {
        Ranker.Candidate(
            id: key(for: entry),
            text: entry.text,
            title: entry.insight?.title ?? "",
            summary: entry.insight?.summary ?? "",
            topics: entry.insight?.topics ?? [],
            people: entry.insight?.people ?? [],
            mood: entry.insight?.mood,
            openLoops: entry.insight?.openLoops ?? [],
            embedding: entry.embedding
        )
    }
}
