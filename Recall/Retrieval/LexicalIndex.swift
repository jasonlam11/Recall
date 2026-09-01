import Foundation

/// Term matching weighted by how rare each term is in the corpus.
///
/// A query term's value as evidence depends on its rarity. "Wayfair" appearing
/// in one entry out of nine is strong evidence about that entry; "work"
/// appearing in six of nine says almost nothing. Inverse document frequency is
/// the standard way to express that, and it's the signal that was missing
/// entirely — retrieval was scoring model-generated tags while ignoring the
/// writer's own words.
nonisolated struct LexicalIndex {

    /// term -> inverse document frequency
    private let idf: [String: Double]
    private let documentCount: Int

    init(documents: [String]) {
        documentCount = documents.count
        var frequency: [String: Int] = [:]
        for document in documents {
            for term in Set(Self.tokenize(document)) {
                frequency[term, default: 0] += 1
            }
        }
        // Smoothed IDF: +1 everywhere keeps a term present in every document
        // from collapsing to zero, and avoids division by zero on an empty set.
        let n = Double(max(documents.count, 1))
        idf = frequency.mapValues { log((n + 1) / (Double($0) + 1)) + 1 }
    }

    /// Fraction of the query's *evidential weight* found in this text.
    ///
    /// Returns 0...1. Denominator is the total IDF of the query's terms, so
    /// matching one rare term scores higher than matching two common ones.
    func score(query: String, against text: String) -> Float {
        let queryTerms = Set(Self.tokenize(query))
        guard !queryTerms.isEmpty else { return 0 }
        let textTerms = Set(Self.tokenize(text))

        var total = 0.0
        var matched = 0.0
        for term in queryTerms {
            // An unseen term is maximally rare, so weight it like a term that
            // appears in exactly one document.
            let weight = idf[term] ?? (log(Double(max(documentCount, 1)) + 1) + 1)
            total += weight
            if textTerms.contains(term) { matched += weight }
        }
        guard total > 0 else { return 0 }
        return Float(matched / total)
    }

    /// Lowercased alphanumeric runs of 3+ characters.
    ///
    /// The length floor drops most stopwords without maintaining a stopword
    /// list, and IDF handles whatever slips through — a term in every document
    /// carries almost no weight regardless.
    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 }
    }
}
