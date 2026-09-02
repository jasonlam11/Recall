import Foundation
import Observation

/// Records which entries the tools actually surfaced during a turn.
///
/// This exists because asking the model for its own citations doesn't work.
/// Requesting them in `instructions` produced none at all; making them a
/// `@Generable` field degraded the prose and broke decoding alongside tools;
/// and extracting them from the finished answer produced *invented* ids —
/// entry 1 cited from a corpus numbered 2 through 12.
///
/// The retrieval layer already knows the ground truth. Provenance is recorded
/// where it's known rather than inferred from what the model claims, which
/// makes it unfakeable: the sources shown to the user are exactly the entries
/// the model was given.
@MainActor
@Observable
final class ToolAudit {

    /// Citation ids surfaced this turn, in the order the tools returned them.
    private(set) var surfaced: [Int] = []

    func reset() { surfaced = [] }

    func record(_ ids: [Int]) {
        for id in ids where !surfaced.contains(id) {
            surfaced.append(id)
        }
    }
}
