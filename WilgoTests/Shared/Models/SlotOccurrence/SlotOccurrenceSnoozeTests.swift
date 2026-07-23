import Foundation
import SwiftData
import Testing
@testable import Wilgo

/// Snooze as a property of a concrete `SlotOccurrence` (parameter-free: the occurrence already
/// knows its slot + psychDay). Replaces the time-parameterized `Slot.isSnoozed(at:)`. Cases that
/// only existed because the old API took an arbitrary time (wrong time-of-day / wrong recurrence
/// day → false) are moot here: a `SlotOccurrence` cannot be built for a day the slot does not fire.
extension SlotOccurrenceSuite {
@Suite(.serialized)
final class SlotOccurrenceSnoozeTests {
    // MARK: - Helpers
    @MainActor
    private func makeSlot(
        startHour: Int, endHour: Int,
        recurrence: SlotRecurrence = .everyDay,
        in ctx: ModelContext
    ) -> Slot {
        let slot = Slot(start: timeOfDay(hour: startHour), end: timeOfDay(hour: endHour), recurrence: recurrence)
        let commitment = Commitment(
            title: "Test",
            cycle: Cycle(kind: .daily, referencePsychDay: testDate(year: 2026, month: 1, day: 1)),
            slots: [slot],
            target: Target(count: 1)
        )
        ctx.insert(commitment)
        ctx.insert(slot)
        return slot
    }

    // MARK: - Tests

    @Test("no snooze → occurrence not snoozed")
    @MainActor func noSnooze_false() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = makeSlot(startHour: 9, endHour: 11, in: ctx)

        let occ = try #require(slot.occurrence(on: testDate(year: 2026, month: 3, day: 5)))
        #expect(occ.isSnoozed == false)
    }

    @Test("snooze for this occurrence's psychDay → snoozed")
    @MainActor func snoozeForThisDay_true() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = makeSlot(startHour: 9, endHour: 11, in: ctx)

        let snooze = SlotSnooze(
            slot: slot, psychDay: testDate(year: 2026, month: 3, day: 5), snoozedAt: testDate(year: 2026, month: 3, day: 5, hour: 10))
        ctx.insert(snooze)

        let occ = try #require(slot.occurrence(on: testDate(year: 2026, month: 3, day: 5)))
        #expect(occ.isSnoozed == true)
    }

    @Test("snooze for a different day → not snoozed for this occurrence")
    @MainActor func snoozeForOtherDay_false() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = makeSlot(startHour: 9, endHour: 11, in: ctx)

        // Stale snooze recorded for the 4th.
        let stale = SlotSnooze(
            slot: slot, psychDay: testDate(year: 2026, month: 3, day: 4), snoozedAt: testDate(year: 2026, month: 3, day: 4, hour: 10))
        ctx.insert(stale)

        let occ = try #require(slot.occurrence(on: testDate(year: 2026, month: 3, day: 5)))
        #expect(occ.isSnoozed == false)
    }

    @Test("cross-midnight: snooze anchored to the start day matches the occurrence")
    @MainActor func crossMidnight_snoozeOnStartDay_true() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // Slot 11pm–1am; the occurrence on Dec 31 spans into Jan 1.
        let slot = makeSlot(startHour: 23, endHour: 1, in: ctx)

        // Snooze is anchored to the firing's start day (Dec 31), per slot.snooze(at:in:).
        let snooze = SlotSnooze(
            slot: slot, psychDay: testDate(year: 2025, month: 12, day: 31), snoozedAt: testDate(year: 2026, month: 1, day: 1, hour: 0, minute: 30))
        ctx.insert(snooze)

        let occ = try #require(slot.occurrence(on: testDate(year: 2025, month: 12, day: 31)))
        #expect(occ.isSnoozed == true)
    }
}
}
