import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite(.serialized)
final class CommitmentSlotStatusSnoozeTests {
    private func tod(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2000
        c.month = 1
        c.day = 1
        c.hour = hour
        c.minute = minute
        c.second = 0
        return Calendar.current.date(from: c)!
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        c.minute = minute
        c.second = 0
        return Calendar.current.date(from: c)!
    }

    @MainActor
    private func makeCommitment(slots slotDefs: [(start: Int, end: Int)], in ctx: ModelContext) -> Commitment {
        let anchor = date(year: 2026, month: 1, day: 1)
        let slots = slotDefs.map { Slot(start: tod(hour: $0.start), end: tod(hour: $0.end)) }
        let c = Commitment(
            title: "Test",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: slots,
            target: Target(count: 1)
        )
        ctx.insert(c)
        slots.forEach { ctx.insert($0) }
        return c
    }

    @Test("active slot, not snoozed → kind is .insideSlot")
    @MainActor func notSnoozed_isInsideSlot() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(slots: [(9, 11)], in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        #expect(c.slotStatus(now: now).kind == .insideSlot)
    }

    @Test("9–11am snoozed, 3–5pm slot remains → kind is .beforeNextToday")
    @MainActor func snoozedSlot_dropsToBeforeNextToday() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(slots: [(9, 11), (15, 17)], in: ctx)
        commitment.cycle = Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 1, day: 1))
        commitment.target = Target(count: 2)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let slot = try #require(commitment.slots.first)
        ctx.insert(SlotSnooze(slot: slot, psychDay: date(year: 2026, month: 3, day: 5), snoozedAt: now))

        let status = commitment.slotStatus(now: now)
        #expect(status.kind == .beforeNextToday)
        #expect(status.remainingSlots.allSatisfy { $0.start > now })
    }

    @Test("sole slot snoozed, no other slots → kind is .noSlotToday, behindCount > 0")
    @MainActor func soleSlotSnoozed_noSlotToday_behindCountPositive() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(slots: [(9, 11)], in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let slot = try #require(commitment.slots.first)
        ctx.insert(SlotSnooze(slot: slot, psychDay: date(year: 2026, month: 3, day: 5), snoozedAt: now))

        let slotSt = commitment.slotStatus(now: now)
        let progress = commitment.goalProgress(now: now)
        let behindCount = progress.leftToDo.map { max(0, $0 - slotSt.remainingSlots.count) }

        #expect(slotSt.kind == .noSlotToday)
        #expect(slotSt.remainingSlots.isEmpty)
        #expect(behindCount == 1)
    }

    @Test("snooze on today's occurrence does not affect future occurrences (weekly cycle)")
    @MainActor func snoozeDoesNotAffectFutureOccurrence() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11), recurrence: .everyDay)
        let commitment = Commitment(
            title: "Test",
            cycle: Cycle(kind: .weekly, referencePsychDay: date(year: 2026, month: 3, day: 2)),
            slots: [slot],
            target: Target(count: 2)
        )
        ctx.insert(commitment)
        ctx.insert(slot)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        ctx.insert(SlotSnooze(slot: slot, psychDay: date(year: 2026, month: 3, day: 5), snoozedAt: now))

        let slotSt = commitment.slotStatus(now: now)
        #expect(slotSt.remainingSlots.contains { $0.start > now }, "Future occurrences should not be filtered by today's snooze")
    }
}
