import Foundation
import SwiftData
import Testing

@testable import Wilgo

@Suite("SlotSnooze.slotPsychDay", .serialized)
final class SlotPsychDayTests {

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
    private func makeSlot(
        startHour: Int, endHour: Int,
        recurrence: SlotRecurrence = .everyDay,
        in ctx: ModelContext
    ) -> Slot {
        let anchor = date(year: 2026, month: 1, day: 1)
        let slot = Slot(start: tod(hour: startHour), end: tod(hour: endHour), recurrence: recurrence)
        let commitment = Commitment(
            title: "Test",
            slots: [slot],
            target: QuantifiedCycle(cycle: Cycle(kind: .daily, referencePsychDay: anchor), count: 1)
        )
        ctx.insert(commitment)
        ctx.insert(slot)
        return slot
    }

    // MARK: - Normal (non-cross-midnight) slot

    @Test("normal slot: returns psychDay of time")
    @MainActor func normal_returnsCurrentPsychDay() throws {
        let container = try makeContainer()
        let slot = makeSlot(startHour: 9, endHour: 11, in: container.mainContext)

        let time = date(year: 2026, month: 3, day: 5, hour: 10)
        let psychDay = try SlotSnooze.slotPsychDay(slot: slot, at: time, calendar: .current)

        let expected = date(year: 2026, month: 3, day: 5)
        #expect(Calendar.current.isDate(psychDay, inSameDayAs: expected))
    }

    // MARK: - Cross-midnight slot

    @Test("cross-midnight: time is pre-midnight (11:30pm) → psychDay is that same calendar day")
    @MainActor func crossMidnight_preMidnight_returnsSameDay() throws {
        let container = try makeContainer()
        // Slot 11pm–1am
        let slot = makeSlot(startHour: 23, endHour: 1, in: container.mainContext)

        // 11:30pm Dec 31 — pre-midnight portion
        let time = date(year: 2025, month: 12, day: 31, hour: 23, minute: 30)
        let psychDay = try SlotSnooze.slotPsychDay(slot: slot, at: time, calendar: .current)

        let expected = date(year: 2025, month: 12, day: 31)
        #expect(Calendar.current.isDate(psychDay, inSameDayAs: expected))
    }

    @Test("cross-midnight: time is post-midnight (12:30am Jan 1) → psychDay is previous calendar day (Dec 31)")
    @MainActor func crossMidnight_postMidnight_returnsPreviousDay() throws {
        let container = try makeContainer()
        // Slot 11pm–1am
        let slot = makeSlot(startHour: 23, endHour: 1, in: container.mainContext)

        // 12:30am Jan 1 — post-midnight portion, occurrence started Dec 31
        let time = date(year: 2026, month: 1, day: 1, hour: 0, minute: 30)
        let psychDay = try SlotSnooze.slotPsychDay(slot: slot, at: time, calendar: .current)

        let expected = date(year: 2025, month: 12, day: 31)
        #expect(Calendar.current.isDate(psychDay, inSameDayAs: expected))
    }

    // MARK: - Throws when slot inactive

    @Test("wrong time of day → throws slotNotActive")
    @MainActor func inactive_wrongTime_throws() throws {
        let container = try makeContainer()
        // Slot 9am–11am; time is 3pm (outside window)
        let slot = makeSlot(startHour: 9, endHour: 11, in: container.mainContext)

        let time = date(year: 2026, month: 3, day: 5, hour: 15)
        #expect(throws: SlotSnooze.SlotPsychDayError.slotNotActive) {
            try SlotSnooze.slotPsychDay(slot: slot, at: time, calendar: .current)
        }
    }

    @Test("wrong recurrence day → throws slotNotActive")
    @MainActor func inactive_wrongDay_throws() throws {
        let container = try makeContainer()
        // Monday-only slot; time is a Tuesday
        let slot = makeSlot(startHour: 9, endHour: 11, recurrence: .specificWeekdays([2]), in: container.mainContext)

        // Jan 6 2026 is a Tuesday — correct time, wrong day
        let tuesday = date(year: 2026, month: 1, day: 6, hour: 10)
        #expect(throws: SlotSnooze.SlotPsychDayError.slotNotActive) {
            try SlotSnooze.slotPsychDay(slot: slot, at: tuesday, calendar: .current)
        }
    }
}
