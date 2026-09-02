import Testing
@testable import Recall

/// Tests for the "exchanges left" estimate.
///
/// Only the arithmetic is tested. Counting tokens needs a loaded model, but the
/// arithmetic is the part that was wrong, so it's the part worth pinning.
@MainActor
struct ContextBudgetTests {

    @Test("Divides remaining budget by recent turn cost")
    func basicEstimate() {
        // 2400 left, turns costing 400 -> 6 more.
        #expect(ContextBudget.exchanges(remaining: 2400, turnCosts: [400, 400, 400]) == 6)
    }

    @Test("Averages only recent turns, not the whole conversation")
    func usesTrailingWindow() {
        // An early cheap turn must not make the estimate optimistic now: the
        // last three turns cost 400 each, so 100 at the start is ignored.
        let withEarlyCheapTurn = ContextBudget.exchanges(
            remaining: 2400, turnCosts: [100, 400, 400, 400]
        )
        #expect(withEarlyCheapTurn == 6)
    }

    @Test("Tracks a rising turn cost")
    func adaptsToCostIncrease() {
        // Turns are getting more expensive; the estimate should fall.
        let cheap = ContextBudget.exchanges(remaining: 2400, turnCosts: [200, 200, 200])
        let costly = ContextBudget.exchanges(remaining: 2400, turnCosts: [200, 600, 800])
        #expect(cheap > costly)
    }

    @Test("Falls back to a guess before any turn completes")
    func firstTurn() {
        let estimate = ContextBudget.exchanges(remaining: 3500, turnCosts: [])
        #expect(estimate >= 1)
        #expect(estimate <= 10, "a 3500-token budget can't hold more than a handful of turns")
    }

    @Test("Never reports a negative or absurd count")
    func degenerate() {
        #expect(ContextBudget.exchanges(remaining: 0, turnCosts: [400]) == 0)
        // A zero-cost turn must not divide by zero.
        #expect(ContextBudget.exchanges(remaining: 1000, turnCosts: [0]) == 1000)
    }

    @Test("Rounds down, so the warning errs early")
    func roundsDown() {
        // 2399 / 400 = 5.99 -> 5, not 6.
        #expect(ContextBudget.exchanges(remaining: 2399, turnCosts: [400]) == 5)
    }
}
