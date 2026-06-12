import Foundation
import Testing
@testable import Wilgo

@MainActor
struct StreakSummaryTests {
    // `outcomes` is most-recent-first. Index 0 is the cycle being reported (always
    // failed, since the streak summary only shows on failed cards).

    // MARK: - Case 1: consecutive failures (2+)

    @Test func twoConsecutiveFailures() {
        let s = StreakSummary.summarize(recentOutcomes: [.failed, .failed, .passed])
        #expect(s == "2 consecutive failed cycles")
    }

    @Test func fourConsecutiveFailures() {
        let s = StreakSummary.summarize(
            recentOutcomes: [.failed, .failed, .failed, .failed, .passed]
        )
        #expect(s == "4 consecutive failed cycles")
    }

    @Test func allFailuresInWindow() {
        let s = StreakSummary.summarize(recentOutcomes: [.failed, .failed, .failed])
        #expect(s == "3 consecutive failed cycles")
    }

    // MARK: - Case 2: first failure after a win streak

    @Test func firstFailureAfterWins() {
        let s = StreakSummary.summarize(
            recentOutcomes: [.failed, .passed, .passed, .passed]
        )
        #expect(s == "First failure after 3 consecutive wins")
    }

    @Test func firstFailureAfterSingleWin_singular() {
        let s = StreakSummary.summarize(recentOutcomes: [.failed, .passed])
        #expect(s == "First failure after 1 consecutive win")
    }

    @Test func firstFailureCountsOnlyTheImmediateWinStreak() {
        // current fail, two wins, then an older fail → win streak is 2.
        let s = StreakSummary.summarize(
            recentOutcomes: [.failed, .passed, .passed, .failed]
        )
        #expect(s == "First failure after 2 consecutive wins")
    }

    // MARK: - Case 1 takes priority over Case 2

    @Test func consecutiveFailuresPreferredOverWinStreak() {
        let s = StreakSummary.summarize(
            recentOutcomes: [.failed, .failed, .passed, .passed]
        )
        #expect(s == "2 consecutive failed cycles")
    }

    // MARK: - Nil cases (not enough context)

    @Test func singleFailureNoHistoryReturnsNil() {
        #expect(StreakSummary.summarize(recentOutcomes: [.failed]) == nil)
    }

    @Test func emptyHistoryReturnsNil() {
        #expect(StreakSummary.summarize(recentOutcomes: []) == nil)
    }
}
