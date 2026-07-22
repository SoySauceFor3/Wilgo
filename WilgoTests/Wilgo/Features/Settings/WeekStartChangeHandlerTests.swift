import Foundation
import Testing
@testable import Wilgo

private func makeWeeklyCommitment(anchoredOn anchor: Date) -> Commitment {
    Commitment(
        title: "Test",
        cycle: Cycle(kind: .weekly, referencePsychDay: anchor),
        slots: [],
        target: Target(count: 3)
    )
}

@Suite
struct WeekStartChangeHandlerTests {
    // MARK: affectedCommitments

    @Test("affectedCommitments: Mon-anchored commitment is affected when switching to Sunday")
    func monAnchoredAffectedWhenSwitchingToSunday() {
        let monday = testDate(year: 2026, month: 3, day: 30)
        let c = makeWeeklyCommitment(anchoredOn: monday)
        let affected = WeekStartChangeHandler.affectedCommitments([c], newStartsOnMonday: false)
        #expect(affected.count == 1)
    }

    @Test("affectedCommitments: Sun-anchored commitment is not affected when switching to Sunday")
    func sunAnchoredNotAffectedWhenSwitchingToSunday() {
        let sunday = testDate(year: 2026, month: 3, day: 29)
        let c = makeWeeklyCommitment(anchoredOn: sunday)
        let affected = WeekStartChangeHandler.affectedCommitments([c], newStartsOnMonday: false)
        #expect(affected.isEmpty)
    }

    @Test("affectedCommitments: daily commitment is never affected")
    func dailyCommitmentNotAffected() {
        let today = testDate(year: 2026, month: 3, day: 30)
        let c = Commitment(
            title: "Daily",
            cycle: Cycle(kind: .daily, referencePsychDay: today),
            slots: [],
            target: Target(count: 1)
        )
        let affected = WeekStartChangeHandler.affectedCommitments([c], newStartsOnMonday: false)
        #expect(affected.isEmpty)
    }

    // MARK: newCurrentCycleStart / newCurrentCycleEnd

    @Test("newCurrentCycleStart: Thursday → prior Sunday when switching to Sunday-start")
    func cycleStartThursdayToSunday() {
        let thursday = testDate(year: 2026, month: 4, day: 2)
        let expectedSunday = testDate(year: 2026, month: 3, day: 29)
        let start = WeekStartChangeHandler.newCurrentCycleStart(
            newStartsOnMonday: false, today: thursday)
        #expect(start == expectedSunday)
    }

    @Test("newCurrentCycleEnd: 7 days after start")
    func cycleEndIsSevenDaysAfterStart() throws {
        let thursday = testDate(year: 2026, month: 4, day: 2)
        let start = WeekStartChangeHandler.newCurrentCycleStart(
            newStartsOnMonday: false, today: thursday)
        let end = WeekStartChangeHandler.newCurrentCycleEnd(
            newStartsOnMonday: false, today: thursday)
        let diff = try #require(Calendar.current.dateComponents([.day], from: start, to: end).day)
        #expect(diff == 7)
        let expectedEnd = testDate(year: 2026, month: 4, day: 5)
        #expect(end == expectedEnd)
    }

    // MARK: apply

    @Test("newCurrentCycleStart: on Sunday itself returns that same Sunday when switching to Sunday-start")
    func cycleStartOnBoundaryDay() {
        let sunday = testDate(year: 2026, month: 3, day: 29)
        let start = WeekStartChangeHandler.newCurrentCycleStart(
            newStartsOnMonday: false, today: sunday)
        #expect(start == sunday)
    }

    @Test("apply: re-anchors commitment to new cycle start")
    func applyReanchorsCommitment() {
        let monday = testDate(year: 2026, month: 3, day: 30)
        let c = makeWeeklyCommitment(anchoredOn: monday)
        let thursday = testDate(year: 2026, month: 4, day: 2)
        let expectedSunday = testDate(year: 2026, month: 3, day: 29)

        WeekStartChangeHandler.apply(
            to: [c], newStartsOnMonday: false, today: thursday)

        #expect(c.cycle.anchorPsychDay == expectedSunday)
    }

    @Test("apply: target mode remains unchanged")
    func applyDoesNotChangeTargetMode() {
        let monday = testDate(year: 2026, month: 3, day: 30)
        let c = makeWeeklyCommitment(anchoredOn: monday)
        let thursday = testDate(year: 2026, month: 4, day: 2)

        WeekStartChangeHandler.apply(
            to: [c], newStartsOnMonday: false, today: thursday)

        #expect(c.target.configuredMode == .on)
    }
}
