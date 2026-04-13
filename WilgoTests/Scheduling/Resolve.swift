import Foundation
import Testing

@testable import Wilgo

// MARK: - Helpers

/// Builds a concrete Date at the given y/m/d h:m using the same calendar as Time.
private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = hour
    comps.minute = minute
    comps.second = 0
    return Calendar.current.date(from: comps)!
}

/// Returns a reference Date whose *only* meaningful fields are hour and minute —
/// same as how Slot stores its start/end times.
private func timeOfDay(hour: Int, minute: Int = 0) -> Date {
    date(year: 2000, month: 1, day: 1, hour: hour, minute: minute)
}

@Suite("Time.resolve(timeOfDay:on:)")
struct TimeResolveTests {

    @Test("morning time lands on the same calendar day")
    func morningLandsSameday() {
        let day = date(year: 2026, month: 1, day: 1)
        let result = Time.resolve(timeOfDay: timeOfDay(hour: 8), on: day)
        #expect(result == date(year: 2026, month: 1, day: 1, hour: 8))
    }

    @Test("midnight (00:00) time")
    func midnight() {
        let day = date(year: 2026, month: 1, day: 1)
        let result = Time.resolve(timeOfDay: timeOfDay(hour: 0), on: day)
        #expect(result == date(year: 2026, month: 1, day: 1, hour: 0))
    }

    @Test("late-night time")
    func lateNight() {
        let day = date(year: 2026, month: 1, day: 1)
        let result = Time.resolve(timeOfDay: timeOfDay(hour: 23, minute: 30), on: day)
        #expect(result == date(year: 2026, month: 1, day: 1, hour: 23, minute: 30))
    }

    @Test("minute component is preserved")
    func minutePreserved() {
        let day = date(year: 2026, month: 1, day: 1)
        let result = Time.resolve(timeOfDay: timeOfDay(hour: 9, minute: 45), on: day)
        #expect(result == date(year: 2026, month: 1, day: 1, hour: 9, minute: 45))
    }

    @Test("non-midnight day param is normalised to midnight")
    func dirtyDayNormalised() {
        let day = date(year: 2026, month: 1, day: 1, hour: 23)
        let result = Time.resolve(timeOfDay: timeOfDay(hour: 23), on: day)
        #expect(result == date(year: 2026, month: 1, day: 1, hour: 23))
    }
}
