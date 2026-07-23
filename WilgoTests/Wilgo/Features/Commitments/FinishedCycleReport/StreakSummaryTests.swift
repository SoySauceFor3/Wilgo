import Foundation
import Testing
@testable import Wilgo

extension FinishedCycleReportSuite {
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

    @Test func firstFailureCountsOnlyTheImmediateWinStreak() {
        // current fail, two wins, then an older fail → win streak is 2.
        let s = StreakSummary.summarize(
            recentOutcomes: [.failed, .passed, .passed, .failed]
        )
        #expect(s == "First failure after 2 consecutive wins")
    }

    // MARK: - Case 3: flaky ratio (single-win gap, multiple failures in window)

    @Test func flakyPatternUsesRatio() {
        // F P F P F P → not consecutive, immediate win streak is only 1,
        // window has 3 failures of 6 → report the honest ratio.
        let s = StreakSummary.summarize(
            recentOutcomes: [.failed, .passed, .failed, .passed, .failed, .passed]
        )
        #expect(s == "Failed 3 of the last 6 cycles")
    }

    @Test func singleWinGapWithEarlierFailureUsesRatio() {
        // F P F → immediate win streak is 1, two failures in window of 3.
        let s = StreakSummary.summarize(recentOutcomes: [.failed, .passed, .failed])
        #expect(s == "Failed 2 of the last 3 cycles")
    }

    @Test func genuineSingleSlipAfterOneWinThenNothingIsGentle() {
        // F P only — one slip after a single win, no earlier failures.
        // Not flaky; keep the gentle Case 2 message.
        let s = StreakSummary.summarize(recentOutcomes: [.failed, .passed])
        #expect(s == "First failure after 1 consecutive win")
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
}
