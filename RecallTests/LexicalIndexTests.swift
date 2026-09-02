import Testing
@testable import Recall

struct LexicalIndexTests {

    /// Mirrors the real failure: "kestrel" appears once, "work" appears
    /// everywhere. A query for the rare term must not be outranked.
    private let corpus = [
        "Waiting on the Kestrel offer and it is making me anxious about work",
        "Long day of work on the dashboard, nothing else to report",
        "More work today, same as yesterday, tired of work",
        "Went for a run and thought about work a little",
    ]

    @Test("Within one query, the rare term carries most of the weight")
    func rarityDominatesWithinAQuery() {
        // Scores are normalized by the query's total IDF, so comparing across
        // two different queries is meaningless by design. Only ranking within
        // a single query matters. This asserts that property directly: for
        // "kestrel work", the rare term is worth more than the common one.
        let index = LexicalIndex(documents: corpus)
        let rareOnly = index.score(query: "kestrel work", against: "kestrel")
        let commonOnly = index.score(query: "kestrel work", against: "work")
        #expect(rareOnly > commonOnly)
        #expect(rareOnly + commonOnly == 1.0, "the two halves should partition the query weight")
    }

    @Test("A fully matched query scores one")
    func fullMatch() {
        let index = LexicalIndex(documents: corpus)
        #expect(index.score(query: "kestrel", against: corpus[0]) == 1.0)
    }

    @Test("An absent term scores zero")
    func noMatch() {
        let index = LexicalIndex(documents: corpus)
        #expect(index.score(query: "kestrel", against: corpus[1]) == 0)
        #expect(index.score(query: "kayaking", against: corpus[0]) == 0)
    }

    @Test("Matching a rare term beats matching a common one in a two-term query")
    func partialMatchPrefersRareTerm() {
        let index = LexicalIndex(documents: corpus)
        // "kestrel work": doc 0 has both, doc 1 has only the common term.
        let both = index.score(query: "kestrel work", against: corpus[0])
        let commonOnly = index.score(query: "kestrel work", against: corpus[1])
        #expect(both == 1.0)
        #expect(commonOnly < 0.5, "matching only the common term is weak evidence")
    }

    @Test("Empty query and empty corpus are handled")
    func degenerate() {
        #expect(LexicalIndex(documents: corpus).score(query: "", against: corpus[0]) == 0)
        #expect(LexicalIndex(documents: []).score(query: "anything", against: "text") == 0)
    }

    @Test("Tokenizer keeps content words and lowercases them")
    func tokenizerKeepsContentWords() {
        let tokens = LexicalIndex.tokenize("Kestrel offer finally arrived")
        #expect(tokens.contains("kestrel"))
        #expect(tokens.contains("offer"))
        #expect(tokens.contains("arrived"))
    }

    @Test("Tokenizer drops function words")
    func tokenizerDropsFunctionWords() {
        // Determiners, prepositions, and pronouns carry structure, not meaning.
        let tokens = LexicalIndex.tokenize("nervous about the future with them")
        #expect(tokens.contains("nervous"))
        #expect(tokens.contains("future"))
        #expect(!tokens.contains("the"), "determiner should be dropped")
        #expect(!tokens.contains("about"), "preposition should be dropped")
        #expect(!tokens.contains("with"), "preposition should be dropped")
        #expect(!tokens.contains("them"), "pronoun should be dropped")
    }
}

extension LexicalIndexTests {

    /// The bug this guards: an earlier IDF formula added a +1 floor, so a word
    /// in every document still scored 1.0. "nervous about the future" then
    /// ranked an unrelated entry third on the strength of "the".
    @Test("A term in every document contributes nothing")
    func universalTermIsWorthless() {
        let docs = [
            "the quick brown fox jumped",
            "the lazy dog slept all day",
            "the rain fell on the roof",
        ]
        let index = LexicalIndex(documents: docs)
        // "the" is in all three, so a query of only "the" has zero weight.
        #expect(index.score(query: "the", against: docs[0]) == 0)
        // And it can't prop up a query alongside a real term.
        #expect(index.score(query: "the fox", against: docs[1]) == 0,
                "matching only the universal term is no evidence")
        #expect(index.score(query: "the fox", against: docs[0]) == 1.0)
    }
}

extension LexicalIndexTests {

    /// The bug this guards: "have" is tagged a verb by NLTagger, so grammatical
    /// filtering keeps it. On its own it let the query "the about have with"
    /// return three confident results against a corpus about nothing of the
    /// kind. Frequency catches what grammar misses.
    @Test("A term in more than half the corpus carries no evidence")
    func commonTermsCarryNoEvidence() {
        let docs = [
            "i have been running most mornings",
            "i have a meeting about the roadmap",
            "i have not called home in weeks",
            "kayaking on the river at dawn",
        ]
        let index = LexicalIndex(documents: docs)
        // "have" is in 3 of 4, above the half-corpus threshold.
        #expect(index.score(query: "have", against: docs[0]) == 0)
        // A genuinely rare term still scores.
        #expect(index.score(query: "kayaking", against: docs[3]) == 1.0)
    }
}

extension LexicalIndexTests {

    /// The bug this guards: NLTagger classified an unfamiliar proper noun as an
    /// interjection when it was followed by another word, so grammatical
    /// filtering silently deleted it. `tokenize("kestrel work")` returned
    /// `["work"]`, losing the single most valuable kind of query term.
    @Test("An unfamiliar proper noun survives tokenization")
    func rareProperNounSurvives() {
        #expect(LexicalIndex.tokenize("kestrel") == ["kestrel"])
        #expect(LexicalIndex.tokenize("kestrel work") == ["kestrel", "work"])
        #expect(LexicalIndex.tokenize("kestrel offer").contains("kestrel"))
        // And it still scores as the rare, high-value term it is.
        let corpus = ["kestrel decision pending", "ordinary work day", "another work day"]
        let index = LexicalIndex(documents: corpus)
        #expect(index.score(query: "kestrel", against: corpus[0]) == 1.0)
    }
}
