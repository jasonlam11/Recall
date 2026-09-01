import Foundation
import SwiftData

/// Finds entries relevant to a natural-language query.
///
/// Deliberately hybrid. Vector similarity alone was measured to rank unrelated
/// entries above relevant ones (see NOTES.md), so it contributes one signal
/// among several rather than deciding the order by itself. The structured
/// signals are available *because* enrichment already distilled each entry into
/// topics, people, and a mood — the retriever gets to reuse that work.
@MainActor
final class RetrievalService {

    /// A structured query. Tools in the intelligence layer build these; the
    /// retriever never parses natural language itself.
    struct Query {
        var text: String = ""
        var people: [String] = []
        var topics: [String] = []
        var mood: Mood?
        var dateRange: ClosedRange<Date>?
        var limit: Int = 5
    }

    struct Result: Identifiable {
        let entry: JournalEntry
        let score: Float
        /// Why this entry matched — surfaced in the UI so ranking is legible.
        let reasons: [String]
        var id: PersistentIdentifier { entry.id }
    }

    private let embeddings: EmbeddingService

    /// Relative weight of each signal. Kept as named constants rather than
    /// magic numbers so the evaluation harness can sweep them later.
    private static let vectorWeight: Float = 0.5
    private static let topicWeight: Float = 0.3
    private static let personWeight: Float = 0.15
    private static let moodWeight: Float = 0.05

    init(embeddings: EmbeddingService) {
        self.embeddings = embeddings
    }

    func search(_ query: Query, in allEntries: [JournalEntry]) async -> [Result] {
        // 1. Hard filters first: they only ever shrink the candidate set, so
        //    doing them before any vector math is strictly cheaper.
        var candidates = allEntries
        if let range = query.dateRange {
            candidates = candidates.filter { range.contains($0.createdAt) }
        }
        if let mood = query.mood {
            candidates = candidates.filter { $0.insight?.mood == mood }
        }
        guard !candidates.isEmpty else { return [] }

        // 2. Vector signal, centered against this corpus.
        var vectorScores: [PersistentIdentifier: Float] = [:]
        if !query.text.isEmpty {
            let vectors = candidates.compactMap(\.embedding)
            if vectors.count > 1, let queryVector = try? await embeddings.vector(for: query.text) {
                let centroid = Vector.centroid(of: vectors)
                let centeredQuery = Vector.centered(queryVector, centroid: centroid)
                for entry in candidates {
                    guard let v = entry.embedding else { continue }
                    let similarity = Vector.cosineSimilarity(
                        centeredQuery, Vector.centered(v, centroid: centroid)
                    )
                    vectorScores[entry.id] = max(0, similarity)
                }
            }
        }
        let ceiling = vectorScores.values.max() ?? 0

        // 3. Combine.
        let results: [Result] = candidates.map { entry in
            var score: Float = 0
            var reasons: [String] = []

            if ceiling > 0, let raw = vectorScores[entry.id] {
                // Normalized against the best match so weights stay comparable
                // regardless of the absolute cosine range for this corpus.
                score += Self.vectorWeight * (raw / ceiling)
            }

            let insight = entry.insight
            let topicHits = overlap(query.topics + tokens(query.text), with: insight?.topics ?? [])
            if !topicHits.isEmpty {
                score += Self.topicWeight
                reasons.append("topic: \(topicHits.joined(separator: ", "))")
            }
            let personHits = overlap(query.people + tokens(query.text), with: insight?.people ?? [])
            if !personHits.isEmpty {
                score += Self.personWeight
                reasons.append("person: \(personHits.joined(separator: ", "))")
            }
            if let mood = query.mood, insight?.mood == mood {
                score += Self.moodWeight
                reasons.append("mood: \(mood.rawValue)")
            }
            if reasons.isEmpty && score > 0 { reasons.append("similar in meaning") }

            return Result(entry: entry, score: score, reasons: reasons)
        }

        return results
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(query.limit)
            .map { $0 }
    }

    // MARK: - Text helpers

    /// Lowercased words of length > 3, which drops most stopwords without
    /// maintaining a stopword list.
    private func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 3 }
    }

    /// Case-insensitive substring overlap in either direction, so "work" matches
    /// "work deadlines" and "Priya" matches "priya".
    private func overlap(_ needles: [String], with haystack: [String]) -> [String] {
        var found: [String] = []
        for item in haystack {
            let lowerItem = item.lowercased()
            for needle in needles {
                let n = needle.lowercased()
                guard n.count > 2 else { continue }
                if lowerItem.contains(n) || n.contains(lowerItem) {
                    found.append(item)
                    break
                }
            }
        }
        return found
    }
}
