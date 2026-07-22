import Foundation
import SwiftData
import Testing
@testable import Wilgo

extension SchedulingSuite {
@Suite(.serialized)
final class CommitmentGoalProgressTests {
    private func tod(hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2000
        c.month = 1
        c.day = 1
        c.hour = hour
        c.minute = 0
        c.second = 0
        return Calendar.current.date(from: c)!
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        c.minute = 0
        c.second = 0
        return Calendar.current.date(from: c)!
    }

    @MainActor
    private func makeCommitment(
        targetCount: Int,
        targetMode: TargetMode = .on,
        cycleKind: CycleKind = .daily,
        in ctx: ModelContext
    ) -> Commitment {
        let anchor = date(year: 2026, month: 1, day: 1)
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: cycleKind, referencePsychDay: anchor),
            slots: [slot],
            target: Target(count: targetCount, mode: targetMode)
        )
        ctx.insert(c)
        ctx.insert(slot)
        return c
    }

    @MainActor
    private func addCheckIn(to c: Commitment, at date: Date, in ctx: ModelContext) {
        let checkIn = CheckIn(commitment: c, createdAt: date)
        ctx.insert(checkIn)
        c.checkIns.append(checkIn)
    }

    // MARK: - leftToDo / isMet

    @Test("empty check-ins → leftToDo equals target.count; isMet false")
    @MainActor func emptyCheckIns_leftToDoEqualsTarget() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(targetCount: 3, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)

        let progress = c.goalProgress(now: now)

        #expect(progress.leftToDo == 3)
        #expect(progress.isMet == false)
    }

    @Test("some check-ins fewer than target → leftToDo is difference; isMet false")
    @MainActor func someCheckIns_leftToDoIsDifference() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let c = makeCommitment(targetCount: 4, in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 12)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 8), in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 10), in: ctx)

        let progress = c.goalProgress(now: now)

        #expect(progress.leftToDo == 2)
        #expect(progress.isMet == false)
    }

    @Test("check-ins meet target exactly → leftToDo is 0; isMet true")
    @MainActor func exactlyMet_isMetTrue() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let c = makeCommitment(targetCount: 3, in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 18)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 8), in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 10), in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 14), in: ctx)

        let progress = c.goalProgress(now: now)

        #expect(progress.leftToDo == 0)
        #expect(progress.isMet == true)
    }

    @Test("check-ins exceed target → leftToDo is 0; isMet true")
    @MainActor func overTarget_leftToDoIsZero() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let c = makeCommitment(targetCount: 2, in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 18)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 8), in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 10), in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 14), in: ctx)

        let progress = c.goalProgress(now: now)

        #expect(progress.leftToDo == 0)
        #expect(progress.isMet == true)
    }

    @Test("target disabled → leftToDo is nil; isMet false even with sufficient check-ins")
    @MainActor func targetDisabled_leftToDoIsNil_isMetFalse() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let c = makeCommitment(targetCount: 3, targetMode: .disabled, in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 8), in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 10), in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 12)

        let progress = c.goalProgress(now: now)

        #expect(progress.leftToDo == nil)
        #expect(progress.isMet == false)
    }

    // MARK: - Cycle scoping

    @Test("check-ins outside the daily cycle are not counted")
    @MainActor func checkInsOutsideDailyCycle_notCounted() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let c = makeCommitment(targetCount: 3, in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 4, hour: 10), in: ctx) // day before
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 6, hour: 10), in: ctx) // day after
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 10), in: ctx) // in-cycle

        let now = date(year: 2026, month: 3, day: 5, hour: 12)
        let progress = c.goalProgress(now: now)

        #expect(progress.leftToDo == 2)
        #expect(progress.isMet == false)
    }

    @Test("different `now` values resolve to their own daily cycles independently")
    @MainActor func differentNow_recomputesForCorrectCycle() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let c = makeCommitment(targetCount: 3, in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 10), in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 7, hour: 10), in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 7, hour: 14), in: ctx)

        let progressA = c.goalProgress(now: date(year: 2026, month: 3, day: 5, hour: 20))
        let progressB = c.goalProgress(now: date(year: 2026, month: 3, day: 7, hour: 20))

        #expect(progressA.leftToDo == 2)  // 1 check-in on day A
        #expect(progressB.leftToDo == 1)  // 2 check-ins on day B
    }

    @Test("weekly cycle: check-ins inside the week count, outside do not")
    @MainActor func weeklyCycle_checkInsInWeekCounted_outsideNot() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let c = makeCommitment(targetCount: 3, cycleKind: .weekly, in: ctx)

        addCheckIn(to: c, at: date(year: 2026, month: 1, day: 1, hour: 10), in: ctx)  // Thu week 1
        addCheckIn(to: c, at: date(year: 2026, month: 1, day: 3, hour: 10), in: ctx)  // Sat week 1
        addCheckIn(to: c, at: date(year: 2026, month: 1, day: 5, hour: 10), in: ctx)  // Mon week 1
        addCheckIn(to: c, at: date(year: 2026, month: 1, day: 8, hour: 10), in: ctx)  // Thu week 2
        addCheckIn(to: c, at: date(year: 2026, month: 1, day: 9, hour: 10), in: ctx)  // Fri week 2

        let week1 = c.goalProgress(now: date(year: 2026, month: 1, day: 5, hour: 12))
        #expect(week1.leftToDo == 0)
        #expect(week1.isMet == true)

        let week2 = c.goalProgress(now: date(year: 2026, month: 1, day: 10, hour: 12))
        #expect(week2.leftToDo == 1)
        #expect(week2.isMet == false)
    }
}
}
