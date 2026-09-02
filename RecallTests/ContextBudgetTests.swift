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

extension ContextBudgetTests {

    /// The pattern that motivated using the costliest recent turn rather than
    /// the mean: several short questions, then a long one. A mean stays
    /// optimistic until the long turn has already landed.
    @Test("Short turns followed by a long one give a conservative estimate")
    func shortThenLong() {
        let shortTurns = ContextBudget.exchanges(remaining: 2400, turnCosts: [120, 120, 120])
        let afterOneLong = ContextBudget.exchanges(remaining: 2400, turnCosts: [120, 120, 1200])
        #expect(afterOneLong < shortTurns, "one expensive turn should lower the estimate")
        // 2400 / 1200 = 2, not 2400 / 480 = 5.
        #expect(afterOneLong == 2)
    }

    @Test("A single cheap turn after an expensive one stays cautious")
    func doesNotBounceBackImmediately() {
        // The expensive turn is still inside the window, so the estimate
        // shouldn't leap back up on one cheap exchange.
        let estimate = ContextBudget.exchanges(remaining: 2400, turnCosts: [1200, 100])
        #expect(estimate == 2)
    }
}

extension ContextBudgetTests {

    /// Guards the double-count that made `used` a stored counter a liability:
    /// `recordInstructions` is async and fired from a `Task`, so two resets in
    /// quick succession could both land and charge the instructions twice.
    /// Deriving `used` makes that unrepresentable.
    @Test("Used is derived from its parts, so it cannot drift")
    func usedIsDerived() {
        let budget = ContextBudget()
        #expect(budget.used == 0, "a fresh budget has spent nothing")
        budget.reset()
        budget.reset()
        #expect(budget.used == 0, "repeated resets cannot accumulate")
        #expect(budget.turns == 0)
    }

    @Test("A reset budget reports a full window")
    func resetRestoresBudget() {
        let budget = ContextBudget()
        budget.reset()
        #expect(budget.fraction == 0)
        #expect(budget.remaining == max(0, budget.total - 500))
        #expect(budget.exchangesRemaining >= 1)
    }
}
