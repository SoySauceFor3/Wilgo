import Foundation
import SwiftData
import Testing

@testable import Wilgo

@Suite("Slot — resolveOccurrence")
struct SlotResolveOccurrenceTests {

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
        return try ModelContainer(
            for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    // MARK: - Basic resolution

    @Test("resolves time-of-day onto given psychDay")
    @MainActor func resolves_timeOfDay_ontoPsychDay() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        ctx.insert(slot)

        let psychDay = date(year: 2026, month: 4, day: 24)
        let resolved = slot.resolveOccurrence(on: psychDay)

        let resolvedUnwrapped = try #require(resolved)
        let cal = Calendar.current
        #expect(cal.component(.hour, from: resolvedUnwrapped.start) == 9)
        #expect(cal.component(.hour, from: resolvedUnwrapped.end) == 11)
        #expect(cal.component(.day, from: resolvedUnwrapped.start) == 24)
        #expect(cal.component(.month, from: resolvedUnwrapped.start) == 4)
    }

    @Test("preserves original slot id")
    @MainActor func preserves_originalSlotId() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        ctx.insert(slot)

        let psychDay = date(year: 2026, month: 4, day: 24)
        let resolved = try #require(slot.resolveOccurrence(on: psychDay))
        #expect(resolved.id == slot.id)
    }

    // MARK: - Cross-midnight

    @Test("cross-midnight slot: end is pushed to next day")
    @MainActor func crossMidnight_endPushedToNextDay() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 23), end: tod(hour: 1))
        ctx.insert(slot)

        let psychDay = date(year: 2026, month: 4, day: 24)
        let resolved = try #require(slot.resolveOccurrence(on: psychDay))

        let cal = Calendar.current
        #expect(cal.component(.day, from: resolved.start) == 24)
        #expect(cal.component(.hour, from: resolved.start) == 23)
        #expect(cal.component(.day, from: resolved.end) == 25)
        #expect(cal.component(.hour, from: resolved.end) == 1)
    }

    // MARK: - Recurrence filtering

    @Test("specificWeekdays")
    @MainActor func specificWeekdays_excludedDay_returnsNil() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // 2026-04-24 is a Friday (weekday = 6)
        let slot = Slot(
            start: tod(hour: 9), end: tod(hour: 11),
            recurrence: .specificWeekdays([2, 3])  // Mon, Tue only
        )
        ctx.insert(slot)

        let friday = date(year: 2026, month: 4, day: 24)
        #expect(slot.resolveOccurrence(on: friday) == nil)
    }

    @Test("specificWeekdays: returns occurrence on included day")
    @MainActor func specificWeekdays_includedDay_returnsOccurrence() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // 2026-04-24 is a Friday (weekday = 6)
        let slot = Slot(
            start: tod(hour: 9), end: tod(hour: 11),
            recurrence: .specificWeekdays([6])  // Friday
        )
        ctx.insert(slot)

        let friday = date(year: 2026, month: 4, day: 24)
        #expect(slot.resolveOccurrence(on: friday) != nil)
    }

    @Test("everyDay: always returns occurrence")
    @MainActor func everyDay_alwaysReturns() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11), recurrence: .everyDay)
        ctx.insert(slot)

        let psychDay = date(year: 2026, month: 4, day: 24)
        #expect(slot.resolveOccurrence(on: psychDay) != nil)
    }

    @Test("specificMonthDays: returns nil on excluded day")
    @MainActor func specificMonthDays_excludedDay_returnsNil() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(
            start: tod(hour: 9), end: tod(hour: 11),
            recurrence: .specificMonthDays([1, 15])
        )
        ctx.insert(slot)

        let day24 = date(year: 2026, month: 4, day: 24)
        #expect(slot.resolveOccurrence(on: day24) == nil)
    }

    @Test("specificMonthDays: returns occurrence on included day")
    @MainActor func specificMonthDays_includedDay_returnsOccurrence() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(
            start: tod(hour: 9), end: tod(hour: 11),
            recurrence: .specificMonthDays([15, 24])
        )
        ctx.insert(slot)

        let day24 = date(year: 2026, month: 4, day: 24)
        #expect(slot.resolveOccurrence(on: day24) != nil)
    }

    // MARK: - Whole-day slots

    @Test("whole-day slot: resolves to non-nil occurrence")
    @MainActor func wholeDay_returnsOccurrence() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // isWholeDay = start time == end time
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 9))
        ctx.insert(slot)

        let psychDay = date(year: 2026, month: 4, day: 24)
        #expect(slot.resolveOccurrence(on: psychDay) != nil)
    }

    @Test("whole-day slot: end is pushed to next calendar day")
    @MainActor func wholeDay_endPushedToNextDay() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 9))
        ctx.insert(slot)

        let psychDay = date(year: 2026, month: 4, day: 24)
        let resolved = try #require(slot.resolveOccurrence(on: psychDay))

        let cal = Calendar.current
        #expect(cal.component(.day, from: resolved.start) == 24)
        #expect(cal.component(.day, from: resolved.end) == 25)
    }

    @Test("whole-day slot: start and end share the same correct time-of-day")
    @MainActor func wholeDay_startAndEndSameTimeOfDay() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 9))
        ctx.insert(slot)

        let psychDay = date(year: 2026, month: 4, day: 24)
        let resolved = try #require(slot.resolveOccurrence(on: psychDay))

        let cal = Calendar.current
        #expect(cal.component(.hour, from: resolved.start) == 9)
        #expect(cal.component(.hour, from: resolved.end) == 9)
    }

    @Test("whole-day slot: respects recurrence exclusion")
    @MainActor func wholeDay_recurrenceExclusion_returnsNil() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // 2026-04-24 is a Friday (weekday = 6)
        let slot = Slot(
            start: tod(hour: 9), end: tod(hour: 9),
            recurrence: .specificWeekdays([2, 3])  // Mon, Tue only
        )
        ctx.insert(slot)

        let friday = date(year: 2026, month: 4, day: 24)
        #expect(slot.resolveOccurrence(on: friday) == nil)
    }
}
