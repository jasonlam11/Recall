import Foundation
import SwiftData

/// A single journal entry and everything derived from it.
///
/// `insight` and `embedding` are optional by design: an entry is saved the
/// instant the writer finishes, and enrichment happens afterward. A failed or
/// skipped model call leaves a perfectly valid entry with no metadata rather
/// than blocking the save.
@Model
final class JournalEntry {
    var createdAt: Date
    var text: String

    /// Model-generated metadata. `nil` until enrichment succeeds.
    var insight: EntryInsight?

    /// Sentence embedding used for semantic recall. `nil` until indexed.
    var embedding: [Float]?

    init(text: String, createdAt: Date = .now) {
        self.text = text
        self.createdAt = createdAt
    }

    /// True when this entry can participate in semantic search.
    var isIndexed: Bool { embedding?.isEmpty == false }
}
