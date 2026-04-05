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

@Suite("Cycle.makeDefault")
struct CycleDefaultAnchorTests {

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
        let monday = date(year: 2026, month: 3, day: 30)  // 2026-03-30 is a Monday
        #expect(weekday(of: monday) == 2)  // sanity check
        let cycle = Cycle.makeDefault(.weekly, on: monday)
        #expect(cycle.startDayOfCycle(including: monday) == monday)
    }

    @Test("weekly: Wednesday input returns prior Monday")
    func weeklyOnWednesdayReturnsPriorMonday() {
        let wednesday = date(year: 2026, month: 4, day: 1)   // Wed
        let monday    = date(year: 2026, month: 3, day: 30)  // Mon 2 days prior
        let cycle = Cycle.makeDefault(.weekly, on: wednesday)
        #expect(cycle.startDayOfCycle(including: wednesday) == monday)
    }

    @Test("weekly: Sunday input returns prior Monday (6 days back)")
    func weeklyOnSundayReturnsPriorMonday() {
        let sunday = date(year: 2026, month: 4, day: 5)   // Sun
        let monday = date(year: 2026, month: 3, day: 30)  // Mon 6 days prior
        let cycle = Cycle.makeDefault(.weekly, on: sunday)
        #expect(cycle.startDayOfCycle(including: sunday) == monday)
    }

    @Test("weekly: cycle always spans Mon–Sun")
    func weeklyCycleSpansMonToSun() {
        let thursday = date(year: 2026, month: 4, day: 2)
        let expectedStart = date(year: 2026, month: 3, day: 30)  // Mon
        let expectedEnd   = date(year: 2026, month: 4, day: 6)   // following Mon (exclusive)
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
        let firstOfMay   = date(year: 2026, month: 5, day: 1)
        let cycle = Cycle.makeDefault(.monthly, on: midApril)
        #expect(cycle.startDayOfCycle(including: midApril) == firstOfApril)
        #expect(cycle.endDayOfCycle(including: midApril) == firstOfMay)
    }

    // MARK: Backward compatibility — makeDefault does not affect anchored()

    @Test("makeDefault does not modify Cycle.anchored behaviour")
    func anchoredIsUnchanged() {
        let wednesday = date(year: 2026, month: 4, day: 1)
        let via_anchored = Cycle.anchored(.weekly, at: wednesday)
        // anchored() still starts on Wednesday, not Monday
        #expect(via_anchored.startDayOfCycle(including: wednesday) == wednesday)

        let via_makeDefault = Cycle.makeDefault(.weekly, on: wednesday)
        let monday = date(year: 2026, month: 3, day: 30)
        #expect(via_makeDefault.startDayOfCycle(including: wednesday) == monday)
    }
}
