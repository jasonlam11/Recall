import Testing
@testable import Recall

struct EntryInsightTests {

    /// The bug: asked for people in an entry mentioning none, the model returned
    /// `["no people"]`, and the UI rendered a chip reading "no people".
    @Test("Placeholder values are dropped")
    func dropsPlaceholders() {
        #expect(EntryInsight.dropPlaceholders(["no people"], named: "people").isEmpty)
        #expect(EntryInsight.dropPlaceholders(["None"], named: "people").isEmpty)
        #expect(EntryInsight.dropPlaceholders(["n/a", "  "], named: "topics").isEmpty)
        #expect(EntryInsight.dropPlaceholders(["no open loops"], named: "open loops").isEmpty)
        // The field name alone is also a non-answer.
        #expect(EntryInsight.dropPlaceholders(["topics"], named: "topics").isEmpty)
    }

    @Test("Real values survive, including ones that start with \"no\"")
    func keepsRealValues() {
        // A journal entry can legitimately be about no sleep or no response.
        // Dropping these would be a worse bug than the one being fixed.
        #expect(EntryInsight.dropPlaceholders(["no sleep"], named: "topics") == ["no sleep"])
        #expect(EntryInsight.dropPlaceholders(["no response from Wayfair"], named: "open loops")
                == ["no response from Wayfair"])
        #expect(EntryInsight.dropPlaceholders(["Priya", "Marcus"], named: "people") == ["Priya", "Marcus"])
    }

    @Test("Mixed lists keep only the real values")
    func mixed() {
        #expect(EntryInsight.dropPlaceholders(["Priya", "none", "Marcus"], named: "people")
                == ["Priya", "Marcus"])
    }
}
