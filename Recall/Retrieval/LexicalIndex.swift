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
        idf = frequency.mapValues { max(0, log((n + 1) / (Double($0) + 1))) }
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
}
