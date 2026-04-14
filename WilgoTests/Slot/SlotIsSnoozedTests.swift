import Foundation
import SwiftData
import Testing

@testable import Wilgo

@Suite("Slot.isSnoozed", .serialized)
final class SlotIsSnoozedTests {

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
    private func makeSlot(startHour: Int, endHour: Int, in ctx: ModelContext) -> Slot {
        let anchor = date(year: 2026, month: 1, day: 1)
        let slot = Slot(start: tod(hour: startHour), end: tod(hour: endHour))
        let commitment = Commitment(
            title: "Test",
            slots: [slot],
            target: QuantifiedCycle(cycle: Cycle(kind: .daily, referencePsychDay: anchor), count: 1)
        )
        ctx.insert(commitment)
        ctx.insert(slot)
        return slot
    }

    // MARK: - No snooze

    @Test("no snooze → isSnoozed returns false")
    @MainActor func isSnoozed_noSnooze_returnsFalse() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = makeSlot(startHour: 9, endHour: 11, in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        #expect(!slot.isSnoozed(at: now))
    }

    // MARK: - Snoozed today

    @Test("snooze exists for today's psychDay → isSnoozed returns true")
    @MainActor func isSnoozed_snoozeForToday_returnsTrue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = makeSlot(startHour: 9, endHour: 11, in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let psychDay = date(year: 2026, month: 3, day: 5)
        let snooze = SlotSnooze(slot: slot, psychDay: psychDay, snoozedAt: now)
        ctx.insert(snooze)

        #expect(slot.isSnoozed(at: now))
    }

    // MARK: - Snooze from a different day is ignored

    @Test("snooze for yesterday → isSnoozed returns false today")
    @MainActor func isSnoozed_snoozeForYesterday_returnsFalseToday() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = makeSlot(startHour: 9, endHour: 11, in: ctx)

        let yesterday = date(year: 2026, month: 3, day: 4)
        let stale = SlotSnooze(slot: slot, psychDay: yesterday, snoozedAt: yesterday)
        ctx.insert(stale)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        #expect(!slot.isSnoozed(at: now))
    }

    // MARK: - Cross-midnight slot

    @Test("cross-midnight: snooze for Dec 31 (psychDay) → isSnoozed at 12:30am Jan 1 returns true")
    @MainActor func isSnoozed_crossMidnight_postMidnightMatchesPreviousDay() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Slot 11pm–1am; occurrence on Dec 31 extends to 1am Jan 1
        let slot = makeSlot(startHour: 23, endHour: 1, in: ctx)

        let dec31 = date(year: 2025, month: 12, day: 31)
        let snooze = SlotSnooze(slot: slot, psychDay: dec31, snoozedAt: date(year: 2026, month: 1, day: 1, hour: 0))
        ctx.insert(snooze)

        // At 12:30am Jan 1 — still in the Dec 31 occurrence's window
        let at1230 = date(year: 2026, month: 1, day: 1, hour: 0, minute: 30)
        #expect(slot.isSnoozed(at: at1230))
    }

    @Test("cross-midnight: snooze for Dec 31 → isSnoozed at 11pm Dec 31 (pre-midnight) returns true")
    @MainActor func isSnoozed_crossMidnight_preMidnightMatchesCurrentDay() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = makeSlot(startHour: 23, endHour: 1, in: ctx)

        let dec31 = date(year: 2025, month: 12, day: 31)
        let snooze = SlotSnooze(slot: slot, psychDay: dec31, snoozedAt: date(year: 2025, month: 12, day: 31, hour: 23))
        ctx.insert(snooze)

        // At 11:30pm Dec 31 — pre-midnight portion of same occurrence
        let at1130pm = date(year: 2025, month: 12, day: 31, hour: 23, minute: 30)
        #expect(slot.isSnoozed(at: at1130pm))
    }

    @Test("cross-midnight: Jan 1 snooze → isSnoozed at 12:30am Jan 1 returns false (wrong psychDay)")
    @MainActor func isSnoozed_crossMidnight_jan1SnoozeDoesNotMatchDec31Occurrence() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = makeSlot(startHour: 23, endHour: 1, in: ctx)

        // Snooze recorded with psychDay = Jan 1 (wrong — would never be created by SlotSnooze.create,
        // but we verify the matching logic is correct regardless)
        let jan1 = date(year: 2026, month: 1, day: 1)
        let snooze = SlotSnooze(slot: slot, psychDay: jan1, snoozedAt: date(year: 2026, month: 1, day: 1, hour: 0))
        ctx.insert(snooze)

        // At 12:30am Jan 1 — occurrence belongs to Dec 31, so Jan 1 snooze doesn't match
        let at1230 = date(year: 2026, month: 1, day: 1, hour: 0, minute: 30)
        #expect(!slot.isSnoozed(at: at1230))
    }

    // MARK: - Inactive slot → always false

    @Test("wrong time of day (slot inactive) → isSnoozed returns false even with a snooze record")
    @MainActor func isSnoozed_wrongTime_returnsFalse() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Slot 9am–11am; snooze recorded for today's psychDay
        let slot = makeSlot(startHour: 9, endHour: 11, in: ctx)

        let today = date(year: 2026, month: 3, day: 5)
        let snooze = SlotSnooze(slot: slot, psychDay: today, snoozedAt: date(year: 2026, month: 3, day: 5, hour: 10))
        ctx.insert(snooze)

        // 3pm is outside the 9am–11am window — slot not active, so not snoozed
        let at3pm = date(year: 2026, month: 3, day: 5, hour: 15)
        #expect(!slot.isSnoozed(at: at3pm))
    }

    @Test("wrong recurrence day (slot inactive) → isSnoozed returns false even with a snooze record")
    @MainActor func isSnoozed_wrongDay_returnsFalse() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Slot only active on Mondays (weekday 2)
        let anchor = date(year: 2026, month: 1, day: 1)
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11), recurrence: .specificWeekdays([2]))
        let commitment = Commitment(
            title: "Test",
            slots: [slot],
            target: QuantifiedCycle(cycle: Cycle(kind: .daily, referencePsychDay: anchor), count: 1)
        )
        ctx.insert(commitment)
        ctx.insert(slot)

        // Snooze recorded for a Monday
        let monday = date(year: 2026, month: 3, day: 2)  // Monday Mar 2 2026
        let snooze = SlotSnooze(slot: slot, psychDay: monday, snoozedAt: date(year: 2026, month: 3, day: 2, hour: 10))
        ctx.insert(snooze)

        // Tuesday Mar 3 at 10am — correct time but wrong recurrence day
        let tuesday = date(year: 2026, month: 3, day: 3, hour: 10)
        #expect(!slot.isSnoozed(at: tuesday))
    }
}
