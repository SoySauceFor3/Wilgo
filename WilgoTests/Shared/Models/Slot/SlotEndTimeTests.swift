import Foundation
import SwiftData
import Testing
@testable import Wilgo

extension SlotSuite {
struct SlotEndTimeTests {
    @Test("normal slot: end is on the same day")
    @MainActor func normalSlot_endSameDay() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = Slot(start: timeOfDay(hour: 9), end: timeOfDay(hour: 11))
        ctx.insert(slot)

        let day = testDate(year: 2026, month: 4, day: 24)
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
        let slot = Slot(start: timeOfDay(hour: 9, minute: 15), end: timeOfDay(hour: 10, minute: 45))
        ctx.insert(slot)

        let day = testDate(year: 2026, month: 4, day: 24)
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
        let slot = Slot(start: timeOfDay(hour: 23), end: timeOfDay(hour: 1))
        ctx.insert(slot)

        let day = testDate(year: 2026, month: 4, day: 24)
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
        let slot = Slot(start: timeOfDay(hour: 9), end: timeOfDay(hour: 9))
        ctx.insert(slot)

        let day = testDate(year: 2026, month: 4, day: 24)
        let end = slot.endTime(onDayStarting: day)

        let cal = Calendar.current
        #expect(cal.component(.day, from: end) == 25)
        #expect(cal.component(.hour, from: end) == 9)
    }

    @Test("end matches the SlotOccurrence end for the same day")
    @MainActor func matchesOccurrence() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = Slot(start: timeOfDay(hour: 23), end: timeOfDay(hour: 1))
        ctx.insert(slot)

        let day = testDate(year: 2026, month: 4, day: 24)
        let occurrence = try #require(slot.occurrence(on: day))
        #expect(slot.endTime(onDayStarting: day) == occurrence.end)
    }
}
}
