import Foundation

/// Term matching weighted by how rare each term is in the corpus.
///
/// A rare term is strong evidence about the entry containing it. A term in most
/// entries says almost nothing.
nonisolated struct LexicalIndex {

    private let idf: [String: Double]
    private let documentCount: Int

    /// Terms above this share of the corpus carry no evidence.
    private static let commonTermThreshold = 0.5

    init(documents: [String]) {
        documentCount = documents.count
        var frequency: [String: Int] = [:]
        for document in documents {
            for term in Set(Self.tokenize(document)) {
                frequency[term, default: 0] += 1
            }
        }
        // No floor constant: a term in every document must collapse to zero,
        // or stopwords manufacture matches.
        let n = Double(max(documents.count, 1))
        let ceiling = Int(n * Self.commonTermThreshold)
        idf = frequency.reduce(into: [:]) { result, pair in
            let (term, df) = pair
            result[term] = df > ceiling ? 0 : max(0, log((n + 1) / (Double(df) + 1)))
        }
    }

    /// Fraction of the query's evidential weight present in `text`, 0...1.
    ///
    /// Normalised by the query's total IDF, so matching one rare term beats
    /// matching two common ones. Comparable within a query, not across queries.
    func score(query: String, against text: String) -> Float {
        let queryTerms = Set(Self.tokenize(query))
        guard !queryTerms.isEmpty else { return 0 }
        let textTerms = Set(Self.tokenize(text))

        var total = 0.0
        var matched = 0.0
        for term in queryTerms {
            let weight = idf[term] ?? log(Double(max(documentCount, 1)) + 1)
            total += weight
            if textTerms.contains(term) { matched += weight }
        }
        guard total > 0 else { return 0 }
        return Float(matched / total)
    }

    /// Content words only, lowercased.
    ///
    /// A fixed stopword list rather than `NLTagger`. The tagger is contextual
    /// and queries are fragments: it kept "about" in "the about have with", and
    /// dropped "kestrel" from "kestrel work" by tagging an unfamiliar proper
    /// noun as an interjection.
    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 && !stopwords.contains($0) }
    }

    /// English function words. Frequency alone misses these: in a small corpus
    /// a word can be noise and still appear in only a third of entries.
    private static let stopwords: Set<String> = [
        "about", "after", "again", "against", "all", "also", "and", "any", "are",
        "because", "been", "before", "being", "both", "but", "can", "cannot",
        "could", "did", "does", "doing", "done", "down", "during", "each",
        "even", "ever", "every", "for", "from", "had", "has", "have", "having",
        "her", "here", "hers", "him", "his", "how", "into", "its", "itself",
        "just", "like", "made", "make", "many", "may", "might", "more", "most",
        "much", "must", "not", "now", "off", "once", "only", "other", "our",
        "out", "over", "own", "same", "she", "should", "some", "such", "than",
        "that", "the", "their", "them", "then", "there", "these", "they",
        "this", "those", "through", "too", "under", "until", "very", "was",
        "were", "what", "when", "where", "which", "while", "who", "whom",
        "why", "will", "with", "would", "you", "your", "yours",
    ]
}
