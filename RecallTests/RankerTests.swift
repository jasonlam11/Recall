import Testing
@testable import Recall

/// Ranking evaluation against a labeled corpus.
///
/// This is a test, not a report, on purpose. The ranking bug that shipped —
/// weighting the vector signal at 0.5 after measuring it as unreliable — was
/// documented in NOTES.md and contradicted by the code, because nothing checked
/// that the weights followed the measurements. These assertions are that check.
struct RankerTests {

    /// Deliberately mirrors the real corpus: overlapping topics, repeated common
    /// words, one rare proper noun, and entries whose relevance to a query is
    /// carried by meaning rather than shared vocabulary.
    private let corpus: [Ranker.Candidate] = [
        .init(id: "kestrel-grant",
              text: "Still nothing from the Kestrel committee. Refreshing my inbox constantly.",
              title: "Waiting on Kestrel",
              summary: "You are waiting on a decision and feeling anxious about the silence.",
              topics: ["grant application", "funding"], people: [], mood: .anxious),
        .init(id: "chess",
              text: "Broke sixteen hundred rapid tonight. Felt good.",
              title: "Chess Rating",
              summary: "You are proud of a small milestone.",
              topics: ["chess", "milestones"], people: [], mood: .content),
        .init(id: "pool",
              text: "Up early, swam a mile before class. Shoulders are wrecked.",
              title: "Pool Before Class",
              summary: "You kept to your morning routine and trained hard.",
              topics: ["pool", "routine"], people: [], mood: .energized),
        .init(id: "friends",
              text: "Climbed with Ines and Rui, then we all got noodles after.",
              title: "Bouldering With Ines and Rui",
              summary: "You spent the evening with friends climbing and eating.",
              topics: ["bouldering", "food"], people: ["Ines", "Rui"], mood: .content),
        .init(id: "burnout",
              text: "Third weekend in a row at the desk. I cannot make myself care about this.",
              title: "Running Out of Steam",
              summary: "You are exhausted and struggling to care about your work.",
              topics: ["work", "exhaustion"], people: [], mood: .low),
    ]

    private let ranker = Ranker()

    private func topID(_ query: String) -> String? {
        ranker.rank(query: query, candidates: corpus).first?.candidate.id
    }

    // MARK: - Term queries

    @Test("A rare proper noun ranks its entry first")
    func rareProperNoun() {
        // The original failure: this entry ranked sixth, behind unrelated
        // entries matching on vector similarity alone.
        #expect(topID("kestrel") == "kestrel-grant")
    }

    @Test("Topic terms rank their entries first")
    func topicTerms() {
        #expect(topID("chess") == "chess")
        #expect(topID("pool") == "pool")
        #expect(topID("bouldering") == "friends")
    }

    @Test("A person's name ranks the entry mentioning them")
    func personName() {
        #expect(topID("ines") == "friends")
    }

    // MARK: - Stopwords

    @Test("A query of only function words matches nothing")
    func functionWordsOnly() {
        #expect(ranker.rank(query: "the with about them", candidates: corpus).isEmpty)
    }

    @Test("Function words don't drag in unrelated entries")
    func functionWordsDontInflate() {
        // "nervous about the future" once returned five results, ranked partly
        // by the word "the". Only genuinely related entries should survive.
        let results = ranker.rank(query: "about the exhaustion", candidates: corpus)
        #expect(results.count == 1)
        #expect(results.first?.candidate.id == "burnout")
    }

    // MARK: - Thresholds and shape

    @Test("A one-word query doesn't match the whole corpus")
    func scoreFloorApplies() {
        let results = ranker.rank(query: "pool", candidates: corpus)
        #expect(results.count < corpus.count)
    }

    @Test("Nothing relevant returns nothing")
    func noFalsePositives() {
        #expect(ranker.rank(query: "kayaking submarine trombone", candidates: corpus).isEmpty)
    }

    @Test("Every result explains why it matched")
    func resultsAreExplained() {
        for result in ranker.rank(query: "pool", candidates: corpus) {
            #expect(!result.reasons.isEmpty)
        }
    }

    @Test("Results come back in descending score order")
    func ordering() {
        let scores = ranker.rank(query: "writing exhaustion chess", candidates: corpus).map(\.score)
        #expect(scores == scores.sorted(by: >))
    }

    // MARK: - Weights

    @Test("Lexical evidence outweighs the vector signal")
    func lexicalOutweighsVector() {
        // The measured ordering of signal reliability, asserted. If someone
        // reweights these, this test is the thing that objects.
        let weights = Ranker.Weights.default
        #expect(weights.lexical > weights.vector)
        #expect(weights.lexical > weights.topic + weights.person + weights.mood)
    }

    @Test("An exact term match beats a pure vector match")
    func exactBeatsVector() {
        // The pool entry has the term; the burnout entry gets a perfect vector
        // score handed to it. The term must still win.
        var candidates = corpus
        let queryVector: [Float] = [1, 0, 0]
        candidates = candidates.map { candidate in
            .init(id: candidate.id, text: candidate.text, title: candidate.title,
                  summary: candidate.summary, topics: candidate.topics,
                  people: candidate.people, mood: candidate.mood,
                  embedding: candidate.id == "burnout" ? [1, 0, 0] : [0, 1, 0])
        }
        let top = ranker.rank(query: "pool", candidates: candidates,
                              queryEmbedding: queryVector).first
        #expect(top?.candidate.id == "pool")
    }
}
