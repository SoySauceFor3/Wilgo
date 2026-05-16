import Foundation
import SwiftData
import Testing
@testable import Wilgo

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
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, SlotSnooze.self, Tag.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    /// Build a daily-cycle commitment with one morning slot. The slot is incidental for
    /// goalProgress — it only consults `target` and `checkIns`.
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

    @Test("empty check-ins → leftToDo equals target.count; isMet false")
    @MainActor func goalProgress_emptyCheckIns_leftToDoEqualsTarget() throws {
        let container = try makeContainer()
        let c = makeCommitment(targetCount: 3, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)

        let progress = c.goalProgress(now: now)

        #expect(progress.leftToDo == 3)
        #expect(progress.isMet == false)
    }

    @Test("some check-ins fewer than target → leftToDo is difference; isMet false")
    @MainActor func goalProgress_someCheckIns_leftToDoIsDifference() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(targetCount: 4, in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 12)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 8), in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 10), in: ctx)

        let progress = c.goalProgress(now: now)

        #expect(progress.leftToDo == 2)
        #expect(progress.isMet == false)
    }

    @Test("more check-ins than target → leftToDo is 0; isMet true")
    @MainActor func goalProgress_overTarget_leftToDoIsZero() throws {
        let container = try makeContainer()
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

    @Test("check-ins exactly meet target → leftToDo is 0; isMet true")
    @MainActor func goalProgress_exactlyMet_isMetTrue() throws {
        let container = try makeContainer()
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

    @Test("target disabled → leftToDo is nil; isMet false")
    @MainActor func goalProgress_targetDisabled_leftToDoIsNil_isMetFalse() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(targetCount: 3, targetMode: .disabled, in: ctx)
        // Even with check-ins, disabled mode produces nil/false.
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 8), in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 10), in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 12)

        let progress = c.goalProgress(now: now)

        #expect(progress.leftToDo == nil)
        #expect(progress.isMet == false)
    }

    @Test("check-ins outside the cycle are not counted")
    @MainActor func goalProgress_checkInsOutsideCycle_notCounted() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(targetCount: 3, in: ctx)
        // Daily cycle: only check-ins on the same psych day as `now` count.
        // Add some outside-the-cycle check-ins (different days) plus one in-cycle.
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 4, hour: 10), in: ctx) // day before
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 6, hour: 10), in: ctx) // day after
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 10), in: ctx) // in-cycle

        let now = date(year: 2026, month: 3, day: 5, hour: 12)
        let progress = c.goalProgress(now: now)

        // Only the single in-cycle check-in counts: 3 - 1 = 2.
        #expect(progress.leftToDo == 2)
        #expect(progress.isMet == false)
    }

    @Test("different `now` values resolve to different cycles independently")
    @MainActor func goalProgress_differentNow_recomputesForCorrectCycle() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Daily cycle: each day is its own cycle. Add one check-in on day A and
        // two on day B; querying each day must see only that day's check-ins.
        let c = makeCommitment(targetCount: 3, in: ctx)
        let dayA = date(year: 2026, month: 3, day: 5, hour: 10)
        let dayB = date(year: 2026, month: 3, day: 7, hour: 10)
        addCheckIn(to: c, at: dayA, in: ctx)
        addCheckIn(to: c, at: dayB, in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 7, hour: 14), in: ctx)

        let progressA = c.goalProgress(now: date(year: 2026, month: 3, day: 5, hour: 20))
        let progressB = c.goalProgress(now: date(year: 2026, month: 3, day: 7, hour: 20))

        // Day A sees 1 check-in: leftToDo = 3 - 1 = 2.
        #expect(progressA.leftToDo == 2)
        #expect(progressA.isMet == false)
        // Day B sees 2 check-ins: leftToDo = 3 - 2 = 1.
        #expect(progressB.leftToDo == 1)
        #expect(progressB.isMet == false)
    }

    @Test("weekly cycle: check-ins inside the week count, outside do not")
    @MainActor func goalProgress_weeklyCycle_checkInsInWeekCounted_outsideWeekNotCounted() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Weekly cycle anchored at makeCommitment's default reference psych-day
        // (2026-01-01, Thursday). The weekly cycle stepping is +7 days, so:
        //   Week 1: [Jan 1, Jan 8)   (Thu–Wed)
        //   Week 2: [Jan 8, Jan 15)
        let c = makeCommitment(targetCount: 3, cycleKind: .weekly, in: ctx)

        // 3 check-ins on different psych-days within week 1 (Thu, Sat, Mon).
        addCheckIn(to: c, at: date(year: 2026, month: 1, day: 1, hour: 10), in: ctx)  // Thu
        addCheckIn(to: c, at: date(year: 2026, month: 1, day: 3, hour: 10), in: ctx)  // Sat
        addCheckIn(to: c, at: date(year: 2026, month: 1, day: 5, hour: 10), in: ctx)  // Mon
        // 2 check-ins in week 2 (Thu + Fri of the following week).
        addCheckIn(to: c, at: date(year: 2026, month: 1, day: 8, hour: 10), in: ctx)  // Thu (week 2)
        addCheckIn(to: c, at: date(year: 2026, month: 1, day: 9, hour: 10), in: ctx)  // Fri (week 2)

        // Query inside week 1: only the 3 in-week check-ins count → target met.
        let progressWeek1 = c.goalProgress(now: date(year: 2026, month: 1, day: 5, hour: 12))
        #expect(progressWeek1.leftToDo == 0)
        #expect(progressWeek1.isMet == true)

        // Query inside week 2: only the 2 in-week check-ins count → 1 left.
        let progressWeek2 = c.goalProgress(now: date(year: 2026, month: 1, day: 10, hour: 12))
        #expect(progressWeek2.leftToDo == 1)
        #expect(progressWeek2.isMet == false)
    }
}
