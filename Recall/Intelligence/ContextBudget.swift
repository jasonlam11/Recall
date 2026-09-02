import Foundation
import FoundationModels
import Observation

/// Tracks how much of the model's context window a conversation has consumed.
///
/// The window is 4096 tokens and every turn spends from it: the question, the
/// answer, and — usually the largest part — whatever the tools inserted into the
/// transcript. Without this the app lets the user hit the ceiling and only then
/// reports failure, which is a worse experience than saying so in advance.
///
/// The count is an accounting of what this app contributed, not a reading of the
/// framework's internal transcript. It will drift slightly from the model's own
/// bookkeeping, which is why the display is deliberately approximate and why a
/// reserve is held back for the answer still to come.
@MainActor
@Observable
final class ContextBudget {

    private let model = SystemLanguageModel.default

    private(set) var used = 0
    private(set) var turns = 0

    /// Held back so the model always has room to answer.
    private static let reserve = 500

    var total: Int { model.contextSize }
    var remaining: Int { max(0, total - used - Self.reserve) }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    /// Rough number of further exchanges, from this conversation's own average.
    ///
    /// Turn cost varies with how much the tools returned, so an average measured
    /// here beats a constant guessed in advance.
    var exchangesRemaining: Int {
        guard turns > 0, used > 0 else { return max(1, remaining / 450) }
        let perTurn = max(1, used / turns)
        return remaining / perTurn
    }

    var isRunningLow: Bool { exchangesRemaining <= 2 }

    func reset() {
        used = 0
        turns = 0
    }

    /// Adds one completed exchange.
    func record(question: String, answer: String, toolOutput: [String]) async {
        var turnTokens = 0
        for text in [question, answer] + toolOutput where !text.isEmpty {
            turnTokens += (try? await model.tokenCount(for: text)) ?? Self.estimate(text)
        }
        used += turnTokens
        turns += 1
    }

    /// Counts the instructions once, at the start of a conversation.
    func recordInstructions(_ instructions: String) async {
        used += (try? await model.tokenCount(for: Instructions(instructions))) ?? Self.estimate(instructions)
    }

    /// Fallback when the framework can't count: English averages ~4 characters
    /// per token. Only used if `tokenCount` throws, and only to avoid showing
    /// the user a budget that has stopped moving.
    private static func estimate(_ text: String) -> Int { max(1, text.count / 4) }
}
