import Foundation

/// Ranking logic. Plain values in, scores out, no framework dependencies.
///
/// Kept separate from `RetrievalService` so it can be measured without a
/// database. Ranking is the part most likely to be wrong.
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
        let openLoops: [String]
        let embedding: [Float]?

        init(
            id: String, text: String, title: String = "", summary: String = "",
            topics: [String] = [], people: [String] = [], mood: Mood? = nil,
            openLoops: [String] = [], embedding: [Float]? = nil
        ) {
            self.id = id; self.text = text; self.title = title; self.summary = summary
            self.topics = topics; self.people = people; self.mood = mood
            self.openLoops = openLoops; self.embedding = embedding
        }

        /// Everything a query may legitimately match: the writer's own words
        /// first, then the model's derived metadata.
        /// Everything a query may legitimately match.
        ///
        /// `openLoops` was missing at first, so the one question the field
        /// exists to answer returned nothing.
        var searchableText: String {
            [text, title, summary,
             topics.joined(separator: " "),
             people.joined(separator: " "),
             openLoops.joined(separator: " ")]
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
        /// Evidence from everything except the vector.
        let grounded: Bool
    }

    struct Weights {
        var lexical: Float = 0.6
        var topic: Float = 0.2
        var vector: Float = 0.15
        var person: Float = 0.1
        var mood: Float = 0.05
        /// Without a floor, the vector gives every entry a nonzero score and
        /// one word matches the whole corpus.
        var floor: Float = 0.08

        static let `default` = Weights()
    }

    var weights: Weights = .default

    /// Ranks candidates against a query.
    ///
    /// `queryEmbedding` is passed in so this stays synchronous. The caller owns
    /// the async, model-loading part.
    func rank(
        query: String,
        candidates: [Candidate],
        queryEmbedding: [Float]? = nil,
        mood: Mood? = nil,
        limit: Int = 20
    ) -> [Scored] {
        guard !candidates.isEmpty else { return [] }

        // IDF is computed over this candidate set, so rarity is relative to
        // what is being searched.
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
                // Normalised against the best match, since absolute cosine
                // range varies by corpus.
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
            let grounded = !reasons.isEmpty
            if reasons.isEmpty && score > 0 { reasons.append("similar in meaning") }

            return Scored(candidate: candidate, score: score, reasons: reasons,
                          lexical: lexical, vector: vector, grounded: grounded)
        }

        // The vector may reorder results but never admit one.
        //
        // With real embeddings every entry scores nonzero, so nonsense queries
        // returned confident matches. Requiring at least one grounded signal
        // means a query with no evidence returns nothing.
        scored = scored.filter(\.grounded)

        return scored
            .filter { $0.score >= weights.floor }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    /// Case-insensitive substring overlap in either direction.
    private func overlap(_ needles: Set<String>, with haystack: [String]) -> [String] {
        haystack.filter { item in
            let lower = item.lowercased()
            return needles.contains { $0.count > 2 && (lower.contains($0) || $0.contains(lower)) }
        }
    }
}
