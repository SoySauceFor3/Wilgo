import Foundation
import SwiftData
import Testing
@testable import Wilgo

struct SlotEndTimeTests {
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

    @Test("normal slot: end is on the same day")
    @MainActor func normalSlot_endSameDay() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        ctx.insert(slot)

        let day = date(year: 2026, month: 4, day: 24)
        let end = slot.endTime(onDayStarting: day)

        let cal = Calendar.current
        #expect(cal.component(.day, from: end) == 24)
        #expect(cal.component(.month, from: end) == 4)
        #expect(cal.component(.hour, from: end) == 11)
        #expect(cal.component(.minute, from: end) == 0)
    }

    @Test("normal slot with minutes: end carries minute component")
    @MainActor func normalSlot_withMinutes() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 9, minute: 15), end: tod(hour: 10, minute: 45))
        ctx.insert(slot)

        let day = date(year: 2026, month: 4, day: 24)
        let end = slot.endTime(onDayStarting: day)

        let cal = Calendar.current
        #expect(cal.component(.day, from: end) == 24)
        #expect(cal.component(.hour, from: end) == 10)
        #expect(cal.component(.minute, from: end) == 45)
    }

    @Test("cross-midnight slot: end is pushed to next calendar day")
    @MainActor func crossMidnight_endNextDay() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 23), end: tod(hour: 1))
        ctx.insert(slot)

        let day = date(year: 2026, month: 4, day: 24)
        let end = slot.endTime(onDayStarting: day)

        let cal = Calendar.current
        #expect(cal.component(.day, from: end) == 25)
        #expect(cal.component(.hour, from: end) == 1)
    }

    @Test("whole-day slot: end is pushed to next calendar day")
    @MainActor func wholeDay_endNextDay() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // isWholeDay = start time == end time
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 9))
        ctx.insert(slot)

        let day = date(year: 2026, month: 4, day: 24)
        let end = slot.endTime(onDayStarting: day)

        let cal = Calendar.current
        #expect(cal.component(.day, from: end) == 25)
        #expect(cal.component(.hour, from: end) == 9)
    }

    @Test("end matches resolveOccurrence end for the same day")
    @MainActor func matchesResolveOccurrence() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 23), end: tod(hour: 1))
        ctx.insert(slot)

        let day = date(year: 2026, month: 4, day: 24)
        let resolved = try #require(slot.resolveOccurrence(on: day))
        #expect(slot.endTime(onDayStarting: day) == resolved.end)
    }
}
