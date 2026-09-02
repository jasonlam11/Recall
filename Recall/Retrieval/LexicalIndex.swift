import Foundation
import NaturalLanguage

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
    /// Function words are removed by *grammatical class* using `NLTagger`
    /// rather than by a hand-maintained stopword list. IDF alone was not
    /// enough: "the" appears in 8 of 11 entries, not all 11, so it kept a
    /// nonzero weight and the query "nervous about the future" ranked an
    /// unrelated entry on the strength of "the" alone.
    ///
    /// Dropping determiners, prepositions, conjunctions, pronouns, and
    /// particles leaves the words that carry the query's meaning. Untagged
    /// words are kept — an unrecognized word is more likely a name or jargon
    /// than a function word, and those are exactly the high-value terms.
    static func tokenize(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        var terms: [String] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace]
        ) { tag, range in
            let word = text[range].lowercased()
            guard word.count >= 3, word.contains(where: { $0.isLetter || $0.isNumber }) else {
                return true
            }
            if Self.stopwords.contains(String(word)) { return true }
            if let tag, Self.functionWordClasses.contains(tag) { return true }
            terms.append(String(word))
            return true
        }
        return terms
    }

    /// Grammatical classes that carry structure rather than meaning.
    private static let functionWordClasses: Set<NLTag> = [
        .determiner, .preposition, .conjunction, .pronoun, .particle, .interjection
    ]

    /// A floor under the tagger.
    ///
    /// `NLTagger` is context-dependent, which is usually its strength and here
    /// its weakness: it correctly drops "about" from "nervous about the future"
    /// and *keeps* it in the fragment "the about have with", because there's no
    /// grammar left to parse. Queries are frequently fragments.
    ///
    /// Frequency cutoffs don't cover it either — in a twelve-entry corpus a word
    /// can be pure noise and still appear in only a third of entries.
    ///
    /// So: both. The tagger generalizes across languages and inflections; this
    /// list guarantees the worst offenders never ground a result. Standard
    /// practice in information retrieval, and the pragmatic answer over an
    /// elegant one that measurably fails.
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
