import Foundation
import Observation

/// Records what the tools actually returned during a turn.
///
/// Provenance comes from the retrieval layer rather than the model's own
/// account of it. Asking the model produced no citations, a `@Generable` field
/// broke decoding alongside tools, and extracting them from the answer invented
/// ids. This can't be faked.
@MainActor
@Observable
final class ToolAudit {

    /// Citation ids surfaced this turn, in the order the tools returned them.
    private(set) var surfaced: [Int] = []

    /// Raw tool output, for token accounting. The framework inserts this into
    /// the transcript directly, so nothing else sees its cost.
    private(set) var payloads: [String] = []

    func reset() {
        surfaced = []
        payloads = []
    }

    func record(_ ids: [Int]) {
        for id in ids where !surfaced.contains(id) {
            surfaced.append(id)
        }
    }

    func record(payload: String) { payloads.append(payload) }
}
