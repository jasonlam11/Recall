import Foundation

/// Term matching weighted by how rare each term is in the corpus.
///
/// A query term's value as evidence depends on its rarity. "Kestrel" appearing
/// in one entry out of nine is strong evidence about that entry; "work"
/// appearing in six of nine says almost nothing. Inverse document frequency is
/// the standard way to express that, and it's the signal that was missing
/// entirely — retrieval was scoring model-generated tags while ignoring the
/// writer's own words.
nonisolated struct LexicalIndex {

    /// term -> inverse document frequency
    private let idf: [String: Double]
    private let documentCount: Int

    /// A term appearing in more than this share of the corpus is treated as
    /// carrying no evidence, regardless of grammatical class.
    ///
    /// Function-word filtering by `NLTagger` handles determiners, prepositions,
    /// and pronouns, but auxiliaries slip through — "have" is tagged a verb, and
    /// on its own it let the query "the about have with" return three confident
    /// results. Frequency catches what grammar misses.
    private static let commonTermThreshold = 0.5

    init(documents: [String]) {
        documentCount = documents.count
        var frequency: [String: Int] = [:]
        for document in documents {
            for term in Set(Self.tokenize(document)) {
                frequency[term, default: 0] += 1
            }
        }
        // IDF, deliberately *without* a floor constant.
        //
        // An earlier version added +1, so a term appearing in every document
        // still scored 1.0. That let stopwords manufacture matches: the query
        // "nervous about the future" ranked an unrelated entry third on the
        // strength of the word "the" alone. Letting a universal term collapse
        // to exactly 0 is the point — a word in every entry distinguishes
        // nothing, so it should contribute nothing.
        let n = Double(max(documents.count, 1))
        let ceiling = Int(n * Self.commonTermThreshold)
        idf = frequency.reduce(into: [:]) { result, pair in
            let (term, df) = pair
            result[term] = df > ceiling ? 0 : max(0, log((n + 1) / (Double(df) + 1)))
        }
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
            // An unseen term is maximally rare: weight it as if it appeared in
            // no document at all.
            let weight = idf[term] ?? log(Double(max(documentCount, 1)) + 1)
            total += weight
            if textTerms.contains(term) { matched += weight }
        }
        guard total > 0 else { return 0 }
        return Float(matched / total)
    }

    /// Content words only, lowercased.
    ///
    /// Function words come off a fixed list. An earlier version used `NLTagger`
    /// to remove them by grammatical class, which failed twice in opposite
    /// directions:
    ///
    /// - It *kept* "about" in the fragment "the about have with", because there
    ///   was no grammar left to parse, letting stopwords manufacture matches.
    /// - It *dropped* "kestrel" from "kestrel work", tagging an unfamiliar
    ///   proper noun as an interjection. Alone the same word tags as
    ///   `OtherWord` and survives. That silently deleted the single most
    ///   valuable kind of query term — a rare name.
    ///
    /// Both come from the same property: the tagger is contextual, and queries
    /// are short fragments where context is exactly what's missing. A fixed
    /// list is less clever and cannot misclassify a name it has never seen.
    ///
    /// The cost is that the list is English-only, where the tagger generalised
    /// across languages. Worth it: a search engine that loses proper nouns is
    /// broken in a way no amount of generality compensates for.
    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 && !stopwords.contains($0) }
    }

    /// English function words.
    ///
    /// Frequency alone doesn't cover these: in a twelve-entry corpus a word can
    /// be pure noise and still appear in only a third of entries, keeping a
    /// nonzero IDF. Standard practice in information retrieval, and the
    /// pragmatic answer over an elegant one that measurably failed.
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
