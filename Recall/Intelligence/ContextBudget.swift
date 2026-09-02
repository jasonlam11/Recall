import Foundation
import FoundationModels
import Observation

/// Tracks how much of the model's context window a conversation has spent.
///
/// Counts what this app contributed, not the framework's internal transcript,
/// so it drifts slightly. Hence the reserve and the approximate display.
@MainActor
@Observable
final class ContextBudget {

    private let model = SystemLanguageModel.default

    /// Derived rather than stored, so repeated resets can't double-count.
    var used: Int { instructionCost + turnCosts.reduce(0, +) }

    private(set) var turns = 0

    /// Charged once per conversation, so it must not be averaged per turn.
    private var instructionCost = 0

    /// Cost of each completed turn, most recent last.
    private var turnCosts: [Int] = []

    /// Held back so the model always has room to answer.
    private static let reserve = 500

    /// How many recent turns the estimate considers.
    private static let window = 3

    /// Instructions, a short question, five entries, a brief answer.
    private static let firstTurnGuess = 450

    var total: Int { model.contextSize }
    var remaining: Int { max(0, total - used - Self.reserve) }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    var exchangesRemaining: Int {
        Self.exchanges(remaining: remaining, turnCosts: turnCosts)
    }

    /// Pure so it can be tested without loading a model.
    ///
    /// Uses the costliest recent turn, not the mean. Underestimating makes the
    /// user reset early; overestimating fails mid-answer.
    static func exchanges(remaining: Int, turnCosts: [Int]) -> Int {
        let recent = turnCosts.suffix(window)
        guard !recent.isEmpty else { return max(1, remaining / firstTurnGuess) }
        let perTurn = max(1, recent.max() ?? firstTurnGuess)
        return remaining / perTurn
    }

    var isRunningLow: Bool { exchangesRemaining <= 2 }

    func reset() {
        turns = 0
        instructionCost = 0
        turnCosts = []
    }

    /// Records one completed exchange.
    ///
    /// `toolOutput` matters most: tool results go into the transcript without
    /// the caller seeing them, and are usually the bulk of a turn.
    func record(question: String, answer: String, toolOutput: [String]) async {
        var turnTokens = 0
        for text in [question, answer] + toolOutput where !text.isEmpty {
            turnTokens += (try? await model.tokenCount(for: text)) ?? Self.estimate(text)
        }
        turnCosts.append(turnTokens)
        turns += 1
    }

    func recordInstructions(_ instructions: String) async {
        instructionCost = (try? await model.tokenCount(for: Instructions(instructions)))
            ?? Self.estimate(instructions)
    }

    /// Fallback if `tokenCount` throws. English averages ~4 characters a token.
    private static func estimate(_ text: String) -> Int { max(1, text.count / 4) }
}
