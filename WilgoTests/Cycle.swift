import Foundation
import Testing

@testable import Wilgo

// MARK: - Helpers

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

@Suite("Cycle")
struct CyclePeriodMathTests {
    // MARK: - Cycle.clampedMonthDay

    @Suite("Cycle.clampedMonthDay")
    struct ClampedMonthDayTests {

        let cal = Time.calendar

        @Test("target day within month returns that exact date")
        func withinMonth() {
            let ref = date(year: 2026, month: 3, day: 1)
            let result = Cycle.clampedMonthDay(15, inMonthOf: ref, cal: cal)!
            #expect(result == date(year: 2026, month: 3, day: 15))
        }

        @Test("target day 1 always returns the first of the month")
        func firstOfMonth() {
            let ref = date(year: 2026, month: 2, day: 14)
            let result = Cycle.clampedMonthDay(1, inMonthOf: ref, cal: cal)!
            #expect(result == date(year: 2026, month: 2, day: 1))
        }

        @Test("target day equals month length returns the last day exactly (no clamping)")
        func exactLastDay() {
            // Feb 2026 has 28 days; requesting day 28 should not clamp.
            let ref = date(year: 2026, month: 2, day: 1)
            let result = Cycle.clampedMonthDay(28, inMonthOf: ref, cal: cal)!
            #expect(result == date(year: 2026, month: 2, day: 28))
        }

        @Test("target day 31 in February (28 days) clamps to Feb 28")
        func clampDay31ToFeb28() {
            let ref = date(year: 2026, month: 2, day: 1)
            let result = Cycle.clampedMonthDay(31, inMonthOf: ref, cal: cal)!
            #expect(result == date(year: 2026, month: 2, day: 28))
        }

        @Test("target day 29 in non-leap-year February clamps to Feb 28")
        func clampDay29ToFeb28NonLeap() {
            // 2026 is not a leap year.
            let ref = date(year: 2026, month: 2, day: 1)
            let result = Cycle.clampedMonthDay(29, inMonthOf: ref, cal: cal)!
            #expect(result == date(year: 2026, month: 2, day: 28))
        }

        @Test("target day 29 in leap-year February returns Feb 29")
        func day29InLeapYearFeb() {
            // 2028 is a leap year.
            let ref = date(year: 2028, month: 2, day: 1)
            let result = Cycle.clampedMonthDay(29, inMonthOf: ref, cal: cal)!
            #expect(result == date(year: 2028, month: 2, day: 29))
        }

        @Test("target day 31 in a 31-day month returns the 31st")
        func day31InMarch() {
            let ref = date(year: 2026, month: 3, day: 1)
            let result = Cycle.clampedMonthDay(31, inMonthOf: ref, cal: cal)!
            #expect(result == date(year: 2026, month: 3, day: 31))
        }

        @Test("result is always midnight regardless of the reference date's time")
        func resultIsMidnight() {
            let ref = date(year: 2026, month: 5, day: 10, hour: 15, minute: 30)
            let result = Cycle.clampedMonthDay(20, inMonthOf: ref, cal: cal)!
            let comps = cal.dateComponents([.hour, .minute, .second], from: result)
            #expect(comps.hour == 0)
            #expect(comps.minute == 0)
            #expect(comps.second == 0)
        }
    }

    // MARK: - Weekly cycle period start
    //
    // Calendar reference — March 2026:
    //   Sun 1, Mon 2, Tue 3, Wed 4, Thu 5, Fri 6, Sat 7, Sun 8, Mon 9, ...
    //
    // Cycle(kind: .weekly, referencePsychDay: anchor) anchors the period to the anchor's weekday.

    @Suite("Cycle — weekly startDayOfCycle")
    final class WeeklyPeriodStartTests {

        @Test("date is the anchor weekday → period starts today")
        func anchorWeekdayIsToday() {
            // anchor = Thu Mar 5, date = Thu Mar 5 → period starts Mar 5
            let thursday = date(year: 2026, month: 3, day: 5)
            let cycle = Cycle(kind: .weekly, referencePsychDay: thursday)
            #expect(cycle.startDayOfCycle(including: thursday) == thursday)
        }

        @Test("anchor weekday falls earlier this week → period started mid-week")
        func anchorWeekdayEarlierThisWeek() {
            // anchor = Mon Mar 2 (weekday 2), date = Thu Mar 5 → 3 days back → Mar 2
            let monday = date(year: 2026, month: 3, day: 2)
            let thursday = date(year: 2026, month: 3, day: 5)
            let cycle = Cycle(kind: .weekly, referencePsychDay: monday)
            #expect(cycle.startDayOfCycle(including: thursday) == monday)
        }

        @Test("anchor weekday falls later in the week → period started previous week")
        func anchorWeekdayLaterInWeek() {
            // anchor = Fri Feb 27, date = Thu Mar 5 → period started Feb 27
            let prevFriday = date(year: 2026, month: 2, day: 27)
            let thursday = date(year: 2026, month: 3, day: 5)
            let cycle = Cycle(kind: .weekly, referencePsychDay: prevFriday)
            #expect(cycle.startDayOfCycle(including: thursday) == prevFriday)
        }

        @Test("period end is always exactly 7 days after period start")
        func periodSpanIsSevenDays() {
            let cal = Time.calendar
            let anchor = date(year: 2026, month: 3, day: 4)  // Wed
            let cycle = Cycle(kind: .weekly, referencePsychDay: anchor)
            let saturday = date(year: 2026, month: 3, day: 7)
            let start = cycle.startDayOfCycle(including: saturday)
            let end = cycle.endDayOfCycle(including: saturday)
            let diff = cal.dateComponents([.day], from: start, to: end).day!
            #expect(diff == 7)
        }

        @Test("period start rolls back across a month boundary")
        func periodStartCrossesMonthBoundary() {
            // anchor = Sat Feb 28, date = Fri Mar 6 → period started Feb 28
            let prevSaturday = date(year: 2026, month: 2, day: 28)
            let friday = date(year: 2026, month: 3, day: 6)
            let cycle = Cycle(kind: .weekly, referencePsychDay: prevSaturday)
            #expect(cycle.startDayOfCycle(including: friday) == prevSaturday)
        }
    }

    // MARK: - Monthly cycle period start

    @Suite("Cycle — monthly startDayOfCycle")
    final class MonthlyPeriodStartTests {

        @Test("today matches the anchor day → period starts today")
        func anchorDayIsToday() {
            let march5 = date(year: 2026, month: 3, day: 5)
            let cycle = Cycle(kind: .monthly, referencePsychDay: march5)
            #expect(cycle.startDayOfCycle(including: march5) == march5)
        }

        @Test("today is past the anchor day → period started earlier this month")
        func anchorDayEarlierThisMonth() {
            // anchor day = 1, today = Mar 5 → period started Mar 1
            let march1 = date(year: 2026, month: 3, day: 1)
            let march5 = date(year: 2026, month: 3, day: 5)
            let cycle = Cycle(kind: .monthly, referencePsychDay: march1)
            #expect(cycle.startDayOfCycle(including: march5) == march1)
        }

        @Test("today is before the anchor day → period started in the previous month")
        func anchorDayLaterInMonth() {
            // anchor day = 20, today = Mar 5 → period started Feb 20
            let feb20 = date(year: 2026, month: 2, day: 20)
            let march5 = date(year: 2026, month: 3, day: 5)
            let cycle = Cycle(kind: .monthly, referencePsychDay: feb20)
            #expect(cycle.startDayOfCycle(including: march5) == feb20)
        }

        @Test("anchor day 31, today = Feb 15 → period started Jan 31")
        func anchorDay31TodayFeb15() {
            let jan31 = date(year: 2026, month: 1, day: 31)
            let feb15 = date(year: 2026, month: 2, day: 15)
            let cycle = Cycle(kind: .monthly, referencePsychDay: jan31)
            #expect(cycle.startDayOfCycle(including: feb15) == jan31)
        }

        @Test("anchor day 31, today = Feb 28 → period started Feb 28 (clamped)")
        func anchorDay31TodayFeb28() {
            let jan31 = date(year: 2026, month: 1, day: 31)
            let feb28 = date(year: 2026, month: 2, day: 28)
            let cycle = Cycle(kind: .monthly, referencePsychDay: jan31)
            #expect(cycle.startDayOfCycle(including: feb28) == feb28)
        }

        @Test("crosses year boundary: anchor day 15, today = Jan 10 → period started Dec 15 last year")
        func crossesYearBoundary() {
            let dec15 = date(year: 2025, month: 12, day: 15)
            let jan10 = date(year: 2026, month: 1, day: 10)
            let cycle = Cycle(kind: .monthly, referencePsychDay: dec15)
            #expect(cycle.startDayOfCycle(including: jan10) == dec15)
        }
    }

    // MARK: - Monthly cycle next period start (end)

    @Suite("Cycle — monthly endDayOfCycle")
    final class MonthlyEndDayTests {

        @Test("normal month: next period starts on same day-of-month one month later")
        func normalMonthAdvancesOneMonth() {
            // anchor = Mar 15, today = Mar 20 → period started Mar 15 → end = Apr 15
            let march15 = date(year: 2026, month: 3, day: 15)
            let march20 = date(year: 2026, month: 3, day: 20)
            let apr15 = date(year: 2026, month: 4, day: 15)
            let cycle = Cycle(kind: .monthly, referencePsychDay: march15)
            #expect(cycle.endDayOfCycle(including: march20) == apr15)
        }

        @Test("anchor day 31, period started Jan 31 → next period start = Feb 28 (clamped)")
        func nextFromJan31IsClampedToFeb28() {
            let jan31 = date(year: 2026, month: 1, day: 31)
            let feb28 = date(year: 2026, month: 2, day: 28)
            let cycle = Cycle(kind: .monthly, referencePsychDay: jan31)
            #expect(cycle.endDayOfCycle(including: jan31) == feb28)
        }

        @Test("anchor day 31, period started Feb 28 → next period start = Mar 31")
        func nextFromFeb28IsMar31() {
            let jan31 = date(year: 2026, month: 1, day: 31)
            let feb28 = date(year: 2026, month: 2, day: 28)
            let march31 = date(year: 2026, month: 3, day: 31)
            let cycle = Cycle(kind: .monthly, referencePsychDay: jan31)
            #expect(cycle.endDayOfCycle(including: feb28) == march31)
        }

        @Test("period end is always strictly after period start")
        func periodEndIsAfterPeriodStart() {
            let anchor = date(year: 2026, month: 3, day: 5)
            let today = date(year: 2026, month: 3, day: 10)
            let cycle = Cycle(kind: .monthly, referencePsychDay: anchor)
            let start = cycle.startDayOfCycle(including: today)
            let end = cycle.endDayOfCycle(including: today)
            #expect(end > start)
        }
    }

    // MARK: - Daily cycle

    @Suite("Cycle — daily startDayOfCycle")
    struct DailyPeriodTests {

        @Test("daily cycle: start is always the same day as the input")
        func dailyStartIsInputDay() {
            let anchor = date(year: 2026, month: 1, day: 1)
            let cycle = Cycle(kind: .daily, referencePsychDay: anchor)
            let target = date(year: 2026, month: 3, day: 15)
            #expect(cycle.startDayOfCycle(including: target) == target)
        }

        @Test("daily cycle: end is exactly 1 day after start")
        func dailyEndIsNextDay() {
            let anchor = date(year: 2026, month: 1, day: 1)
            let cycle = Cycle(kind: .daily, referencePsychDay: anchor)
            let target = date(year: 2026, month: 3, day: 15)
            let start = cycle.startDayOfCycle(including: target)
            let end = cycle.endDayOfCycle(including: target)
            let diff = Time.calendar.dateComponents([.day], from: start, to: end).day!
            #expect(diff == 1)
        }
    }
}
