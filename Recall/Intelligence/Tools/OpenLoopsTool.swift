import Foundation
import FoundationModels
import SwiftData

/// Lists unresolved threads across the journal.
///
/// This exists because searching for them doesn't work, and can't. Asked "what
/// did I say I'd follow up on?", the model reasonably searched for "follow up"
/// but the words in the `openLoops` field are things like "official offer
/// from Kestrel", never the phrase "follow up". No amount of term matching
/// bridges that.
///
/// The field is already structured, so the answer is a lookup rather than a
/// search. Some questions are retrieval; some are projection. Giving the model
/// a tool per shape beats making one tool pretend to cover both.
struct OpenLoopsTool: Tool {

    let name = "listOpenLoops"
    let description = """
        List the unresolved threads the user has written about — things they said \
        they would do, decide, or return to, and questions they left open. Use \
        this for questions about follow-ups, loose ends, or unfinished business, \
        instead of searching.
        """

    @Generable
    struct Arguments {
        @Guide(description: "Only include entries from the last N days. Omit to cover all time.")
        var daysBack: Int?
    }

    private let store: JournalStore
    private let audit: ToolAudit

    /// Most recent entries to report.
    ///
    /// Unbounded, this returned every entry with an open loop. Fine for a
    /// twelve-entry journal, and thousands of tokens against a 4096-token
    /// window once someone has written for a year. `SearchJournalTool` was
    /// capped from the start; this wasn't, because a projection felt like it
    /// had nothing to limit.
    private static let entryLimit = 12

    init(store: JournalStore, audit: ToolAudit) {
        self.store = store
        self.audit = audit
    }

    func call(arguments: Arguments) async throws -> String {
        await list(since: arguments.daysBack)
    }

    @MainActor
    private func list(since daysBack: Int?) async -> String {
        var entries = store.entries
        if let daysBack, daysBack > 0,
           let cutoff = Calendar.current.date(byAdding: .day, value: -daysBack, to: .now) {
            entries = entries.filter { $0.createdAt >= cutoff }
        }

        let allWithLoops = entries.filter { !($0.insight?.openLoops.isEmpty ?? true) }
        guard !allWithLoops.isEmpty else {
            return "The journal has no unresolved threads recorded."
        }

        // `store.entries` is newest first, so this keeps the most recent.
        let withLoops = Array(allWithLoops.prefix(Self.entryLimit))
        let omitted = allWithLoops.count - withLoops.count

        audit.record(withLoops.map { Citation.id(for: $0) })
        var payload = withLoops.map { entry in
            let date = entry.createdAt.formatted(.dateTime.month().day())
            let loops = (entry.insight?.openLoops ?? []).map { "- " + $0 }.joined(separator: "\n")
            return "[\(Citation.id(for: entry))] \(date)\n\(loops)"
        }.joined(separator: "\n\n")

        // Say so, rather than silently answering from a subset.
        if omitted > 0 {
            payload += "\n\n(\(omitted) older entries with unresolved threads were omitted. "
                + "Tell the user this covers the most recent \(withLoops.count).)"
        }
        audit.record(payload: payload)
        return payload
    }
}
