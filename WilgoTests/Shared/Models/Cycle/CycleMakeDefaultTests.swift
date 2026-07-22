import Foundation
import Testing
@testable import Wilgo

// MARK: - Helpers

private func date(year: Int, month: Int, day: Int) -> Date {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = 0
    comps.minute = 0
    comps.second = 0
    return Calendar.current.date(from: comps)!
}

private func weekday(of date: Date) -> Int {
    Calendar.current.component(.weekday, from: date)  // 1=Sun, 2=Mon, …, 7=Sat
}

// MARK: - Tests

@Suite(.serialized)
struct CycleMakeDefaultTests {
    // MARK: Daily

    @Test("daily: anchor is the given psych-day")
    func dailyAnchorIsGivenDay() {
        let wednesday = date(year: 2026, month: 4, day: 1)
        let cycle = Cycle.makeDefault(.daily, on: wednesday)
        #expect(cycle.startDayOfCycle(including: wednesday) == wednesday)
    }

    // MARK: Weekly — various weekdays

    @Test("weekly: Monday input returns that same Monday")
    func weeklyOnMondayReturnsSameDay() {
        UserDefaults.standard.set(true, forKey: AppSettings.weekStartsOnMondayKey)
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey) }
        let monday = date(year: 2026, month: 3, day: 30)  // 2026-03-30 is a Monday
        #expect(weekday(of: monday) == 2)  // sanity check
        let cycle = Cycle.makeDefault(.weekly, on: monday)
        #expect(cycle.startDayOfCycle(including: monday) == monday)
    }

    @Test("weekly: Wednesday input returns prior Monday")
    func weeklyOnWednesdayReturnsPriorMonday() {
        UserDefaults.standard.set(true, forKey: AppSettings.weekStartsOnMondayKey)
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey) }
        let wednesday = date(year: 2026, month: 4, day: 1)  // Wed
        let monday = date(year: 2026, month: 3, day: 30)  // Mon 2 days prior
        let cycle = Cycle.makeDefault(.weekly, on: wednesday)
        #expect(cycle.startDayOfCycle(including: wednesday) == monday)
    }

    @Test("weekly: Sunday input returns prior Monday (6 days back)")
    func weeklyOnSundayReturnsPriorMonday() {
        UserDefaults.standard.set(true, forKey: AppSettings.weekStartsOnMondayKey)
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey) }
        let sunday = date(year: 2026, month: 4, day: 5)  // Sun
        let monday = date(year: 2026, month: 3, day: 30)  // Mon 6 days prior
        let cycle = Cycle.makeDefault(.weekly, on: sunday)
        #expect(cycle.startDayOfCycle(including: sunday) == monday)
    }

    @Test("weekly: cycle always spans Mon–Sun")
    func weeklyCycleSpansMonToSun() {
        UserDefaults.standard.set(true, forKey: AppSettings.weekStartsOnMondayKey)
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey) }
        let thursday = date(year: 2026, month: 4, day: 2)
        let expectedStart = date(year: 2026, month: 3, day: 30)  // Mon
        let expectedEnd = date(year: 2026, month: 4, day: 6)  // following Mon (exclusive)
        let cycle = Cycle.makeDefault(.weekly, on: thursday)
        #expect(cycle.startDayOfCycle(including: thursday) == expectedStart)
        #expect(cycle.endDayOfCycle(including: thursday) == expectedEnd)
    }

    // MARK: Monthly — various month days

    @Test("monthly: 1st of month returns same day")
    func monthlyOnFirstReturnsSameDay() {
        let first = date(year: 2026, month: 4, day: 1)
        let cycle = Cycle.makeDefault(.monthly, on: first)
        #expect(cycle.startDayOfCycle(including: first) == first)
    }

    @Test("monthly: mid-month input returns 1st of that month")
    func monthlyOnMidMonthReturnsFirst() {
        let midMonth = date(year: 2026, month: 4, day: 15)
        let firstOfApril = date(year: 2026, month: 4, day: 1)
        let cycle = Cycle.makeDefault(.monthly, on: midMonth)
        #expect(cycle.startDayOfCycle(including: midMonth) == firstOfApril)
    }

    @Test("monthly: last day of month returns 1st of that month")
    func monthlyOnLastDayReturnsFirst() {
        let lastOfJan = date(year: 2026, month: 1, day: 31)
        let firstOfJan = date(year: 2026, month: 1, day: 1)
        let cycle = Cycle.makeDefault(.monthly, on: lastOfJan)
        #expect(cycle.startDayOfCycle(including: lastOfJan) == firstOfJan)
    }

    @Test("monthly: cycle end is 1st of next month")
    func monthlyCycleEndIsFirstOfNextMonth() {
        let midApril = date(year: 2026, month: 4, day: 10)
        let firstOfApril = date(year: 2026, month: 4, day: 1)
        let firstOfMay = date(year: 2026, month: 5, day: 1)
        let cycle = Cycle.makeDefault(.monthly, on: midApril)
        #expect(cycle.startDayOfCycle(including: midApril) == firstOfApril)
        #expect(cycle.endDayOfCycle(including: midApril) == firstOfMay)
    }

    // MARK: Weekly — week-start setting

    @Test("weekly: Sunday-start: Monday input returns prior Sunday")
    func weeklyOnMondayReturnsPriorSundayWhenSettingIsSunday() {
        UserDefaults.standard.set(false, forKey: AppSettings.weekStartsOnMondayKey)
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey) }

        let monday = date(year: 2026, month: 3, day: 30)  // Monday
        let sunday = date(year: 2026, month: 3, day: 29)  // Prior Sunday
        let cycle = Cycle.makeDefault(.weekly, on: monday)
        #expect(cycle.startDayOfCycle(including: monday) == sunday)
    }

    @Test("weekly: Sunday-start: Wednesday input returns prior Sunday")
    func weeklyOnWednesdayReturnsPriorSundayWhenSettingIsSunday() {
        UserDefaults.standard.set(false, forKey: AppSettings.weekStartsOnMondayKey)
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey) }

        let wednesday = date(year: 2026, month: 4, day: 1)
        let sunday = date(year: 2026, month: 3, day: 29)
        let cycle = Cycle.makeDefault(.weekly, on: wednesday)
        #expect(cycle.startDayOfCycle(including: wednesday) == sunday)
    }

    @Test("weekly: Monday-start still works when setting explicitly true")
    func weeklyExplicitMondayStartReturnsMonday() {
        UserDefaults.standard.set(true, forKey: AppSettings.weekStartsOnMondayKey)
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey) }

        let wednesday = date(year: 2026, month: 4, day: 1)
        let monday = date(year: 2026, month: 3, day: 30)
        let cycle = Cycle.makeDefault(.weekly, on: wednesday)
        #expect(cycle.startDayOfCycle(including: wednesday) == monday)
    }

    @Test("weekly: default (key absent) behaves as Monday-start")
    func weeklyDefaultWithNoKeyIsMonday() {
        UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey)

        let wednesday = date(year: 2026, month: 4, day: 1)
        let monday = date(year: 2026, month: 3, day: 30)
        let cycle = Cycle.makeDefault(.weekly, on: wednesday)
        #expect(cycle.startDayOfCycle(including: wednesday) == monday)
    }
}
