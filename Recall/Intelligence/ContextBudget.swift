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

    /// Counted once at the start of a conversation, so it must not be charged
    /// to every turn when averaging.
    private var instructionCost = 0

    /// Cost of each completed turn, most recent last.
    private var turnCosts: [Int] = []

    /// Held back so the model always has room to answer.
    private static let reserve = 500

    /// How many recent turns the estimate looks at.
    ///
    /// Averaging the whole conversation lets one cheap turn raise the estimate,
    /// so "exchanges left" could go *up* while usage only ever goes up too.
    private static let window = 3

    /// Used before any turn has completed: instructions, a short question,
    /// five retrieved entries, and a brief answer.
    private static let firstTurnGuess = 450

    var total: Int { model.contextSize }
    var remaining: Int { max(0, total - used - Self.reserve) }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    /// Rough number of further exchanges, from what recent turns actually cost.
    ///
    /// Measured rather than assumed: a question answered from one entry costs a
    /// fraction of one answered from five, so a constant would be wrong in both
    /// directions.
    ///
    /// Excludes `instructionCost`, which is spent once. Dividing it by the turn
    /// count charged a fixed cost as if it recurred, which made the estimate
    /// pessimistic by roughly one exchange early in a conversation and quietly
    /// more accurate later.
    var exchangesRemaining: Int {
        Self.exchanges(remaining: remaining, turnCosts: turnCosts)
    }

    /// The estimate as a pure function, so it can be tested without a model.
    ///
    /// Same reason `Ranker` was extracted from `RetrievalService`: the
    /// arithmetic is the part likely to be wrong, and it shouldn't need a
    /// loaded language model to exercise.
    static func exchanges(remaining: Int, turnCosts: [Int]) -> Int {
        let recent = turnCosts.suffix(window)
        guard !recent.isEmpty else { return max(1, remaining / firstTurnGuess) }
        // The most expensive recent turn, not the average.
        //
        // This is a warning, and the two ways of being wrong are not
        // symmetrical: underestimating means the user resets sooner than they
        // had to, overestimating means they hit an error mid-answer. Several
        // short turns followed by a long one is a normal pattern — a few
        // one-line questions, then pasting in something substantial — and a
        // mean would stay optimistic right up until the long turn landed.
        let perTurn = max(1, recent.max() ?? firstTurnGuess)
        return remaining / perTurn
    }

    var isRunningLow: Bool { exchangesRemaining <= 2 }

    func reset() {
        used = 0
        turns = 0
        instructionCost = 0
        turnCosts = []
    }

    /// Adds one completed exchange.
    func record(question: String, answer: String, toolOutput: [String]) async {
        var turnTokens = 0
        for text in [question, answer] + toolOutput where !text.isEmpty {
            turnTokens += (try? await model.tokenCount(for: text)) ?? Self.estimate(text)
        }
        used += turnTokens
        turnCosts.append(turnTokens)
        turns += 1
    }

    /// Counts the instructions once, at the start of a conversation.
    func recordInstructions(_ instructions: String) async {
        let cost = (try? await model.tokenCount(for: Instructions(instructions)))
            ?? Self.estimate(instructions)
        instructionCost = cost
        used += cost
    }

    /// Fallback when the framework can't count: English averages ~4 characters
    /// per token. Only used if `tokenCount` throws, and only to avoid showing
    /// the user a budget that has stopped moving.
    private static func estimate(_ text: String) -> Int { max(1, text.count / 4) }
}
