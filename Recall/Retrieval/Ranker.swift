import Foundation

/// Pure ranking logic, with no dependency on SwiftData, the model, or SwiftUI.
///
/// This was originally inline in `RetrievalService`, which made it impossible to
/// test or measure without standing up a database. Ranking is the part of
/// retrieval most likely to be wrong and most in need of evaluation, so it lives
/// on its own: plain values in, scores out, synchronous and deterministic.
nonisolated struct Ranker {

    /// Everything ranking is allowed to look at.
    struct Candidate: Identifiable {
        let id: String
        let text: String
        let title: String
        let summary: String
        let topics: [String]
        let people: [String]
        let mood: Mood?
        let embedding: [Float]?

        init(
            id: String, text: String, title: String = "", summary: String = "",
            topics: [String] = [], people: [String] = [], mood: Mood? = nil,
            embedding: [Float]? = nil
        ) {
            self.id = id; self.text = text; self.title = title; self.summary = summary
            self.topics = topics; self.people = people; self.mood = mood
            self.embedding = embedding
        }

        /// Everything a query may legitimately match: the writer's own words
        /// first, then the model's derived metadata.
        var searchableText: String {
            [text, title, summary, topics.joined(separator: " "), people.joined(separator: " ")]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }

    struct Scored {
        let candidate: Candidate
        let score: Float
        let reasons: [String]
        /// Kept separately so evaluation can attribute a result to a signal.
        let lexical: Float
        let vector: Float
    }

    struct Weights {
        var lexical: Float = 0.6
        var topic: Float = 0.2
        var vector: Float = 0.15
        var person: Float = 0.1
        var mood: Float = 0.05
        /// Results below this are dropped. Without a floor the vector signal
        /// gives every entry a nonzero score and one word matches the corpus.
        var floor: Float = 0.08

        static let `default` = Weights()
    }

    var weights: Weights = .default

    /// Ranks candidates against a query.
    ///
    /// `queryEmbedding` is passed in rather than computed here so this stays
    /// synchronous and free of framework dependencies — the caller owns the
    /// async, model-loading part.
    func rank(
        query: String,
        candidates: [Candidate],
        queryEmbedding: [Float]? = nil,
        mood: Mood? = nil,
        limit: Int = 20
    ) -> [Scored] {
        guard !candidates.isEmpty else { return [] }

        // Lexical: IDF computed over this candidate set, so rarity is relative
        // to the corpus being searched.
        let lexicon = LexicalIndex(documents: candidates.map(\.searchableText))
        let queryTerms = Set(LexicalIndex.tokenize(query))

        // Vector: centered against the corpus centroid to counter anisotropy.
        var vectorScores: [String: Float] = [:]
        if let queryEmbedding {
            let vectors = candidates.compactMap(\.embedding)
            if vectors.count > 1 {
                let centroid = Vector.centroid(of: vectors)
                let centeredQuery = Vector.centered(queryEmbedding, centroid: centroid)
                for candidate in candidates {
                    guard let v = candidate.embedding else { continue }
                    vectorScores[candidate.id] = max(0, Vector.cosineSimilarity(
                        centeredQuery, Vector.centered(v, centroid: centroid)
                    ))
                }
            }
        }
        let ceiling = vectorScores.values.max() ?? 0

        var scored: [Scored] = candidates.map { candidate in
            var score: Float = 0
            var reasons: [String] = []

            let lexical = lexicon.score(query: query, against: candidate.searchableText)
            if lexical > 0 {
                score += weights.lexical * lexical
                let present = Set(LexicalIndex.tokenize(candidate.searchableText))
                let hits = queryTerms.filter(present.contains).sorted()
                reasons.append("mentions \"\(hits.joined(separator: ", "))\"")
            }

            var vector: Float = 0
            if ceiling > 0, let raw = vectorScores[candidate.id] {
                // Normalized against the best match so weights stay comparable
                // regardless of this corpus's absolute cosine range.
                vector = raw / ceiling
                score += weights.vector * vector
            }

            if !overlap(queryTerms, with: candidate.topics).isEmpty {
                score += weights.topic
                reasons.append("topic: \(overlap(queryTerms, with: candidate.topics).joined(separator: ", "))")
            }
            if !overlap(queryTerms, with: candidate.people).isEmpty {
                score += weights.person
                reasons.append("person: \(overlap(queryTerms, with: candidate.people).joined(separator: ", "))")
            }
            if let mood, candidate.mood == mood {
                score += weights.mood
                reasons.append("mood: \(mood.rawValue)")
            }
            if reasons.isEmpty && score > 0 { reasons.append("similar in meaning") }

            return Scored(candidate: candidate, score: score, reasons: reasons,
                          lexical: lexical, vector: vector)
        }

        // When the query matches real words somewhere, trust that and drop
        // candidates held up only by the weak vector signal. When nothing
        // matches lexically, the vector ranks — the case it exists for.
        if scored.contains(where: { $0.lexical > 0 }) {
            scored = scored.filter { $0.lexical > 0 || $0.score >= weights.lexical * 0.5 }
        }

        return scored
            .filter { $0.score >= weights.floor }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    /// Case-insensitive substring overlap in either direction, so "work"
    /// matches "work deadlines" and "priya" matches "Priya".
    private func overlap(_ needles: Set<String>, with haystack: [String]) -> [String] {
        haystack.filter { item in
            let lower = item.lowercased()
            return needles.contains { $0.count > 2 && (lower.contains($0) || $0.contains(lower)) }
        }
    }
}
