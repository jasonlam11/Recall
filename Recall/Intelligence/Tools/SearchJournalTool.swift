import Foundation
import FoundationModels
import SwiftData

/// Lets the model search the journal.
///
/// `Arguments` is the query-understanding step. Tool calling is built on guided
/// generation, so the schema itself constrains the query and there's no separate
/// parse pass.
///
/// This closes the gap the evaluation exposed: `Ranker` can't handle "nervous
/// about the future" because "nervous" appears in no entry, but the model
/// rewrites it into terms that do.
struct SearchJournalTool: Tool {

    let name = "searchJournal"
    let description = """
        Search the user's journal entries. Use this whenever answering requires \
        knowing what the user wrote. Returns matching entries with bracketed ids.
        """

    @Generable
    struct Arguments {
        @Guide(
            description: """
                The meaningful content words from the question — nouns, verbs, \
                names, and topics. Do not include words like "the", "about", or \
                "have". Include synonyms the user might have actually written.
                """,
            .maximumCount(8)
        )
        var terms: [String]

        @Guide(description: """
            If the question is about a feeling or mood, set this to the tone \
            being asked about so only matching entries are returned. Leave it \
            out only when the question is not about how the user felt.
            """)
        var mood: Mood?

        @Guide(description: "Only return entries from the last N days. Omit to search all time.")
        var daysBack: Int?
    }

    private let store: JournalStore
    private let retrieval: RetrievalService
    private let audit: ToolAudit

    /// Full entry text costs ~58 tokens per hit against a 4096-token window,
    /// so five hits is ~7% of context.
    private static let hitLimit = 5

    /// Per-entry cap, so one long entry can't consume the whole budget.
    private static let textLimit = 600

    init(store: JournalStore, retrieval: RetrievalService, audit: ToolAudit) {
        self.store = store
        self.retrieval = retrieval
        self.audit = audit
    }

    /// `Tool.call` is `@concurrent` and `JournalEntry` isn't `Sendable`, so
    /// entries can't cross the hop. Access happens in `search(_:)` on the main
    /// actor and only the rendered `String` escapes.
    func call(arguments: Arguments) async throws -> String {
        await search(arguments)
    }

    @MainActor
    private func search(_ arguments: Arguments) async -> String {
        let query = RetrievalService.Query(
            text: arguments.terms.joined(separator: " "),
            mood: arguments.mood,
            dateRange: arguments.daysBack.flatMap(Self.range(lastDays:)),
            limit: Self.hitLimit
        )

        let results = await retrieval.search(query, in: store.entries)
        guard !results.isEmpty else {
            return Self.noMatches(in: store.entries)
        }
        audit.record(results.map { Citation.id(for: $0.entry) })
        let payload = results.map(Self.render).joined(separator: "\n\n")
        audit.record(payload: payload)
        return payload
    }

    /// A bare "no matching entries" sent the model into a retry loop, mutating
    /// its query across four calls. Naming what the journal does contain gives
    /// it something to correct toward, or grounds to stop.
    @MainActor
    private static func noMatches(in entries: [JournalEntry]) -> String {
        let topics = Set(entries.flatMap { $0.insight?.topics ?? [] })
            .sorted()
            .prefix(12)
            .joined(separator: ", ")
        guard !topics.isEmpty else {
            return "No entries matched, and the journal has nothing indexed yet."
        }
        return "No entries matched those terms. Topics that do appear in this journal: "
            + topics
            + ". Either search again using one of these, or tell the user their journal doesn't cover this."
    }

    private static func range(lastDays days: Int) -> ClosedRange<Date>? {
        guard days > 0, let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) else {
            return nil
        }
        return start...Date.now
    }

    /// Renders one hit with full entry text rather than the model's summary.
    ///
    /// Reasoning over its own paraphrase would compound extraction mistakes.
    /// Measured cost is 12 tokens per hit over the summary.
    @MainActor
    private static func render(_ result: RetrievalService.Result) -> String {
        let entry = result.entry
        let date = entry.createdAt.formatted(.dateTime.month().day().year())
        var text = entry.text
        var truncated = false
        if text.count > textLimit {
            text = String(text.prefix(textLimit))
            truncated = true
        }

        var lines = ["[\(Citation.id(for: entry))] \(date)"]
        if let insight = entry.insight {
            lines.append("mood: \(insight.mood.rawValue), topics: \(insight.topics.joined(separator: ", "))")
            if !insight.openLoops.isEmpty {
                lines.append("unresolved: \(insight.openLoops.joined(separator: "; "))")
            }
        }
        lines.append(truncated ? text + "… (truncated)" : text)
        return lines.joined(separator: "\n")
    }
}

/// Short ids the model can cite and the UI can resolve.
///
/// `PersistentIdentifier` stringifies to something long and opaque, wasting
/// tokens and inviting the model to mangle it.
@MainActor
enum Citation {
    private static var forward: [PersistentIdentifier: Int] = [:]
    private static var reverse: [Int: PersistentIdentifier] = [:]
    private static var next = 1

    static func id(for entry: JournalEntry) -> Int {
        if let existing = forward[entry.id] { return existing }
        let assigned = next
        next += 1
        forward[entry.id] = assigned
        reverse[assigned] = entry.id
        return assigned
    }

    static func entryID(for citation: Int) -> PersistentIdentifier? { reverse[citation] }
}
