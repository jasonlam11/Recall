import Testing
@testable import Recall

struct LexicalIndexTests {

    /// Mirrors the real failure: "wayfair" appears once, "work" appears
    /// everywhere. A query for the rare term must not be outranked.
    private let corpus = [
        "Waiting on the Wayfair offer and it is making me anxious about work",
        "Long day of work on the dashboard, nothing else to report",
        "More work today, same as yesterday, tired of work",
        "Went for a run and thought about work a little",
    ]

    @Test("Within one query, the rare term carries most of the weight")
    func rarityDominatesWithinAQuery() {
        // Scores are normalized by the query's total IDF, so comparing across
        // two different queries is meaningless by design — only ranking within
        // a single query matters. This asserts that property directly: for
        // "wayfair work", the rare term is worth more than the common one.
        let index = LexicalIndex(documents: corpus)
        let rareOnly = index.score(query: "wayfair work", against: "wayfair")
        let commonOnly = index.score(query: "wayfair work", against: "work")
        #expect(rareOnly > commonOnly)
        #expect(rareOnly + commonOnly == 1.0, "the two halves should partition the query weight")
    }

    @Test("A fully matched query scores one")
    func fullMatch() {
        let index = LexicalIndex(documents: corpus)
        #expect(index.score(query: "wayfair", against: corpus[0]) == 1.0)
    }

    @Test("An absent term scores zero")
    func noMatch() {
        let index = LexicalIndex(documents: corpus)
        #expect(index.score(query: "wayfair", against: corpus[1]) == 0)
        #expect(index.score(query: "kayaking", against: corpus[0]) == 0)
    }

    @Test("Matching a rare term beats matching a common one in a two-term query")
    func partialMatchPrefersRareTerm() {
        let index = LexicalIndex(documents: corpus)
        // "wayfair work": doc 0 has both, doc 1 has only the common term.
        let both = index.score(query: "wayfair work", against: corpus[0])
        let commonOnly = index.score(query: "wayfair work", against: corpus[1])
        #expect(both == 1.0)
        #expect(commonOnly < 0.5, "matching only the common term is weak evidence")
    }

    @Test("Empty query and empty corpus are handled")
    func degenerate() {
        #expect(LexicalIndex(documents: corpus).score(query: "", against: corpus[0]) == 0)
        #expect(LexicalIndex(documents: []).score(query: "anything", against: "text") == 0)
    }

    @Test("Tokenizer lowercases, splits on punctuation, drops short words")
    func tokenizer() {
        let tokens = LexicalIndex.tokenize("Wayfair's Q4 offer — is it in?")
        #expect(tokens.contains("wayfair"))
        #expect(tokens.contains("offer"))
        #expect(!tokens.contains("is"))   // too short
        #expect(!tokens.contains("it"))   // too short
        #expect(!tokens.contains("wayfair's"))  // apostrophe splits
    }
}
