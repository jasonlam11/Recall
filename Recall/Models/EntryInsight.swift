import Foundation
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

extension EntryInsight {

    /// Removes values that describe the absence of a value.
    ///
    /// Asked for people in an entry mentioning none, the model returned
    /// `["no people"]` — and the UI dutifully rendered a chip reading "no
    /// people". The instructions now forbid it, but instructions are a request
    /// the model may decline, so this is the guarantee.
    ///
    /// Matching is exact against a small set plus "no <field name>", rather
    /// than any string starting with "no". A journal entry can legitimately be
    /// about "no sleep" or "no response", and dropping those would be a worse
    /// bug than the one being fixed.
    static func dropPlaceholders(_ values: [String], named field: String) -> [String] {
        let rejected: Set<String> = [
            "none", "n/a", "na", "nothing", "unknown", "not applicable",
            "no \(field)", field
        ]
        return values.filter { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !normalized.isEmpty && !rejected.contains(normalized)
        }
    }
    /// Assembles a finished insight from the last streamed snapshot.
    ///
    /// `PartiallyGenerated` has every property optional because a snapshot can
    /// arrive mid-generation. Returning `nil` when a field is still missing keeps
    /// "partly generated" from masquerading as a complete result.
    init?(completed partial: EntryInsight.PartiallyGenerated) {
        guard let title = partial.title,
              let summary = partial.summary,
              let mood = partial.mood else { return nil }
        self.title = title
        self.summary = summary
        self.people = Self.dropPlaceholders(partial.people ?? [], named: "people")
        self.topics = Self.dropPlaceholders(partial.topics ?? [], named: "topics")
        self.mood = mood
        self.openLoops = Self.dropPlaceholders(partial.openLoops ?? [], named: "open loops")
    }
}
