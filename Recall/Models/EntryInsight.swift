import FoundationModels

/// Structured metadata the on-device model extracts from a journal entry.
///
/// This is the schema the model generates against. Every `@Guide` here does two
/// jobs: it describes the field in natural language (which the model reads) and,
/// where a constraint is attached, it removes invalid tokens from the sampling
/// distribution entirely. Nothing downstream needs to validate shape.
@Generable
nonisolated struct EntryInsight: Codable, Sendable, Equatable {

    @Guide(description: "An evocative title for this entry, at most six words.")
    var title: String

    @Guide(description: "Two sentences summarizing the entry, addressed to the writer as 'you'.")
    var summary: String

    @Guide(description: "Names of people mentioned in the entry.", .maximumCount(5))
    var people: [String]

    @Guide(description: "Subjects or themes the entry is about, as short noun phrases.", .maximumCount(5))
    var topics: [String]

    @Guide(description: "The dominant emotional tone of the entry.")
    var mood: Mood

    @Guide(description: "Unresolved threads the writer should revisit later.", .maximumCount(3))
    var openLoops: [String]
}
