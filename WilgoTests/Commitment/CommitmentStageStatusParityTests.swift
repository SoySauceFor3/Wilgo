import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite("Commitment - StageStatus Parity", .serialized)
final class CommitmentStageStatusParityTests {

    // MARK: - Helpers

    private func tod(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 1; c.hour = hour; c.minute = minute; c.second = 0
        return Calendar.current.date(from: c)!
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute; c.second = 0
        return Calendar.current.date(from: c)!
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, SlotSnooze.self, Tag.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    @MainActor
    private func makeCommitment(
        slots slotDefs: [(start: Int, end: Int)],
        targetCount: Int = 3,
        targetMode: TargetMode = .on,
        cycleKind: CycleKind = .daily,
        in ctx: ModelContext
    ) -> Commitment {
        let anchor = date(year: 2026, month: 1, day: 1)
        let slots = slotDefs.map { Slot(start: tod(hour: $0.start), end: tod(hour: $0.end)) }
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: cycleKind, referencePsychDay: anchor),
            slots: slots,
            target: Target(count: targetCount, mode: targetMode)
        )
        ctx.insert(c)
        slots.forEach { ctx.insert($0) }
        return c
    }

    @MainActor
    private func addCheckIn(to c: Commitment, at date: Date, in ctx: ModelContext) {
        let checkIn = CheckIn(commitment: c, createdAt: date)
        ctx.insert(checkIn)
        c.checkIns.append(checkIn)
    }

    // MARK: - Enabled-target scenarios

    @Test("enabled + goal met → .metGoal, nextUpSlots empty, behindCount 0")
    @MainActor func stageStatus_enabled_goalMet_isMetGoal() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // target=2, slot active now, both check-ins already done this cycle
        let c = makeCommitment(slots: [(9, 11)], targetCount: 2, in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 8), in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 9, minute: 30), in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let status = c.stageStatus(now: now)

        #expect(status.category == .metGoal)
        #expect(status.nextUpSlots.isEmpty)
        #expect(status.behindCount == 0)
    }

    @Test("enabled + slot active now, goal not met → .current, nextUpSlots non-empty")
    @MainActor func stageStatus_enabled_slotActive_goalNotMet_isCurrent() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], targetCount: 3, in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let status = c.stageStatus(now: now)

        #expect(status.category == .current)
        #expect(!status.nextUpSlots.isEmpty)
        let first = try #require(status.nextUpSlots.first)
        #expect(first.start <= now)
    }

    @Test("enabled + slot starts later today, goal not met → .future, nextUpSlots non-empty")
    @MainActor func stageStatus_enabled_slotFutureToday_goalNotMet_isFuture() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(14, 16)], targetCount: 3, in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let status = c.stageStatus(now: now)

        #expect(status.category == .future)
        #expect(!status.nextUpSlots.isEmpty)
        let first = try #require(status.nextUpSlots.first)
        #expect(first.start > now)
    }

    @Test("enabled + no slot today, leftToDo > remainingSlots → .catchUp, behindCount > 0")
    @MainActor func stageStatus_enabled_noSlotToday_behindNeeded_isCatchUp() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], targetCount: 3, cycleKind: .daily, in: ctx)
        // now is after the slot (slot 9-11, now = 18:00) → noSlotToday
        // leftToDo = 3, remainingSlots = 0 → behindCount = 3
        let now = date(year: 2026, month: 3, day: 5, hour: 18)
        let status = c.stageStatus(now: now)

        #expect(status.category == .catchUp)
        #expect(status.behindCount > 0)
    }

    @Test("enabled + no slot today, leftToDo <= remainingSlots in weekly cycle → .others, behindCount 0")
    @MainActor func stageStatus_enabled_noSlotToday_sufficientRemaining_isOthers() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Weekly cycle anchored on Thursday 2026-01-01.
        // Slot at 9-11am every day. now = Thursday 2026-01-01 at 18:00 (past slot).
        // Remaining slots for the cycle = Friday 9-11, Sat 9-11, ... through Wed = 6 slots.
        // targetCount=1, no check-ins → leftToDo=1, remainingSlots=6 → behindCount=0
        let c = makeCommitment(slots: [(9, 11)], targetCount: 1, cycleKind: .weekly, in: ctx)

        let now = date(year: 2026, month: 1, day: 1, hour: 18)
        let status = c.stageStatus(now: now)

        #expect(status.category == .others)
        #expect(status.behindCount == 0)
    }

    // MARK: - Target-disabled scenarios

    @Test("disabled + slot active now → .current, behindCount 0")
    @MainActor func stageStatus_disabled_slotActive_isCurrent() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], targetMode: .disabled, in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let status = c.stageStatus(now: now)

        #expect(status.category == .current)
        #expect(status.behindCount == 0)
    }

    @Test("disabled + slot future today → .future, behindCount 0")
    @MainActor func stageStatus_disabled_slotFutureToday_isFuture() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(15, 17)], targetMode: .disabled, in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let status = c.stageStatus(now: now)

        #expect(status.category == .future)
        #expect(status.behindCount == 0)
        #expect(!status.nextUpSlots.isEmpty)
    }

    @Test("disabled + no slot today → .others, behindCount 0")
    @MainActor func stageStatus_disabled_noSlotToday_isOthers() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Slot already passed (9-11am, now = 18:00). Daily cycle so no future slots.
        let c = makeCommitment(slots: [(9, 11)], targetMode: .disabled, in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 18)
        let status = c.stageStatus(now: now)

        #expect(status.category == .others)
        #expect(status.behindCount == 0)
    }

    // MARK: - Cross-check parity tests

    @Test("parity: enabled current — stageStatus consistent with slotStatus + goalProgress")
    @MainActor func parity_enabled_current_consistentWithDerivation() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], targetCount: 3, in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let slotSt = c.slotStatus(now: now)
        let goalProg = c.goalProgress(now: now)
        let stageSt = c.stageStatus(now: now)

        // Independent assertions on raw derivations
        #expect(slotSt.kind == .insideSlot)
        #expect(goalProg.isMet == false)
        let leftToDo = try #require(goalProg.leftToDo)

        // Wrapper must agree
        #expect(stageSt.category == .current)
        #expect(slotSt.remainingSlots.count == 1)
        let expectedBehind = max(0, leftToDo - slotSt.remainingSlots.count)
        #expect(stageSt.behindCount == expectedBehind)
        #expect(stageSt.behindCount == 2)
    }

    @Test("parity: enabled catchUp — stageStatus consistent with slotStatus + goalProgress")
    @MainActor func parity_enabled_catchUp_consistentWithDerivation() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Daily cycle, slot already passed, goal not met → behindCount > 0
        let c = makeCommitment(slots: [(9, 11)], targetCount: 3, in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 18)
        let slotSt = c.slotStatus(now: now)
        let goalProg = c.goalProgress(now: now)
        let stageSt = c.stageStatus(now: now)

        // Independent assertions on raw derivations
        #expect(slotSt.kind == .noSlotToday)
        #expect(goalProg.isMet == false)
        let leftToDo = try #require(goalProg.leftToDo)

        // Wrapper must agree
        #expect(stageSt.category == .catchUp)
        #expect(slotSt.remainingSlots.count == 0)
        let expectedBehind = max(0, leftToDo - slotSt.remainingSlots.count)
        #expect(stageSt.behindCount == expectedBehind)
        #expect(stageSt.behindCount == 3)
    }

    @Test("parity: disabled others — stageStatus consistent with slotStatus + goalProgress")
    @MainActor func parity_disabled_others_consistentWithDerivation() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Daily cycle, slot already passed, target disabled
        let c = makeCommitment(slots: [(9, 11)], targetMode: .disabled, in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 18)
        let slotSt = c.slotStatus(now: now)
        let goalProg = c.goalProgress(now: now)
        let stageSt = c.stageStatus(now: now)

        // Independent assertions on raw derivations
        #expect(slotSt.kind == .noSlotToday)
        #expect(goalProg.leftToDo == nil)
        #expect(goalProg.isMet == false)

        // Wrapper must agree
        #expect(stageSt.category == .others)
        #expect(stageSt.behindCount == 0)
    }
}
