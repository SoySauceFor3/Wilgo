import Foundation
import SwiftData
import Testing

@testable import Wilgo

/// Tests that Commitment.stageStatus correctly hides snoozed slot occurrences.
@Suite("Commitment.stageStatus — snooze filtering", .serialized)
final class CommitmentStageSnoozeTests {

    // MARK: - Helpers

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, SlotSnooze.self, Tag.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func tod(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 1
        c.hour = hour; c.minute = minute; c.second = 0
        return Calendar.current.date(from: c)!
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute; c.second = 0
        return Calendar.current.date(from: c)!
    }

    @MainActor
    private func makeCommitment(slots slotDefs: [(start: Int, end: Int)], in ctx: ModelContext) -> Commitment {
        let anchor = date(year: 2026, month: 1, day: 1)
        let slots = slotDefs.map { Slot(start: tod(hour: $0.start), end: tod(hour: $0.end)) }
        let commitment = Commitment(
            title: "Test",
            slots: slots,
            target: QuantifiedCycle(cycle: Cycle(kind: .daily, referencePsychDay: anchor), count: 1)
        )
        ctx.insert(commitment)
        slots.forEach { ctx.insert($0) }
        return commitment
    }

    // MARK: - Not snoozed: stageStatus is .current

    @Test("active slot, not snoozed → stageStatus is .current")
    @MainActor func stageStatus_notSnoozed_isCurrent() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(slots: [(9, 11)], in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        #expect(commitment.stageStatus(now: now).category == .current)
    }

    // MARK: - Snoozed: stageStatus becomes .future (next slot exists later today)

    @Test("only slot is snoozed → stageStatus drops from .current to .future (next slot later)")
    @MainActor func stageStatus_snoozedSlot_dropsToCatchUp() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Two slots: 9–11am (snoozed) and 3–5pm (not snoozed)
        let commitment = makeCommitment(slots: [(9, 11), (15, 17)], in: ctx)
        commitment.target = QuantifiedCycle(
            cycle: Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 1, day: 1)),
            count: 2
        )

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let slot = commitment.slots.first(where: { _ in true })!

        // Snooze the 9–11am slot
        let psychDay = date(year: 2026, month: 3, day: 5)
        ctx.insert(SlotSnooze(slot: slot, psychDay: psychDay, snoozedAt: now))

        // Now only the 3pm slot remains active → category becomes .future
        let status = commitment.stageStatus(now: now)
        #expect(status.category == .future)
        // nextUpSlots should only contain the 3pm occurrence
        #expect(status.nextUpSlots.allSatisfy { $0.start > now })
    }

    @Test("sole slot snoozed, no other slots → stageStatus is .catchUp")
    @MainActor func stageStatus_soleSlotSnoozed_becomesCatchUp() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(slots: [(9, 11)], in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let slot = commitment.slots.first!

        // Snooze the only slot
        let psychDay = date(year: 2026, month: 3, day: 5)
        ctx.insert(SlotSnooze(slot: slot, psychDay: psychDay, snoozedAt: now))

        let status = commitment.stageStatus(now: now)
        // No remaining slots with target=1, leftToDo=1, remainingSlots=0 → catchUp
        #expect(status.category == .catchUp)
        #expect(status.nextUpSlots.isEmpty)
    }

    // MARK: - Future slot not affected by today's snooze

    @Test("snooze on current slot does not affect tomorrow's occurrence")
    @MainActor func stageStatus_snoozeDoesNotAffectFutureOccurrence() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // weekly commitment with 2 targets per week
        let anchor = date(year: 2026, month: 3, day: 2)  // Monday
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        let commitment = Commitment(
            title: "Test",
            slots: [slot],
            target: QuantifiedCycle(
                cycle: Cycle(kind: .weekly, referencePsychDay: anchor),
                count: 2
            )
        )
        ctx.insert(commitment)
        ctx.insert(slot)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)  // Thursday

        // Snooze Thursday's occurrence
        let psychDay = date(year: 2026, month: 3, day: 5)
        ctx.insert(SlotSnooze(slot: slot, psychDay: psychDay, snoozedAt: now))

        let status = commitment.stageStatus(now: now)
        // Thursday is gone but Friday (Mar 6) and Sat (Mar 7) occurrences remain
        // so category should still have upcoming slots
        let hasSlotAfterNow = status.nextUpSlots.contains { $0.start > now }
        #expect(hasSlotAfterNow, "Future occurrences should not be filtered by today's snooze")
    }
}
