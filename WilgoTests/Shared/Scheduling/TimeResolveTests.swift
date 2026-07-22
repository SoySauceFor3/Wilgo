import Foundation
import Testing
@testable import Wilgo

extension SchedulingSuite {
struct TimeResolveTests {
    @Test("morning time lands on the same calendar day")
    func morningLandsSameday() {
        let day = testDate(year: 2026, month: 1, day: 1)
        let result = Time.resolve(timeOfDay: timeOfDay(hour: 8), on: day)
        #expect(result == testDate(year: 2026, month: 1, day: 1, hour: 8))
    }

    @Test("midnight (00:00) time")
    func midnight() {
        let day = testDate(year: 2026, month: 1, day: 1)
        let result = Time.resolve(timeOfDay: timeOfDay(hour: 0), on: day)
        #expect(result == testDate(year: 2026, month: 1, day: 1, hour: 0))
    }

    @Test("late-night time")
    func lateNight() {
        let day = testDate(year: 2026, month: 1, day: 1)
        let result = Time.resolve(timeOfDay: timeOfDay(hour: 23, minute: 30), on: day)
        #expect(result == testDate(year: 2026, month: 1, day: 1, hour: 23, minute: 30))
    }

    @Test("minute component is preserved")
    func minutePreserved() {
        let day = testDate(year: 2026, month: 1, day: 1)
        let result = Time.resolve(timeOfDay: timeOfDay(hour: 9, minute: 45), on: day)
        #expect(result == testDate(year: 2026, month: 1, day: 1, hour: 9, minute: 45))
    }

    @Test("non-midnight day param is normalised to midnight")
    func dirtyDayNormalised() {
        let day = testDate(year: 2026, month: 1, day: 1, hour: 23)
        let result = Time.resolve(timeOfDay: timeOfDay(hour: 23), on: day)
        #expect(result == testDate(year: 2026, month: 1, day: 1, hour: 23))
    }
}
}
