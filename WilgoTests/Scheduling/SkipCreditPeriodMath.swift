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

@Suite("SkipCredit")
struct SkipCreditPeriodMathTests {
    // MARK: - SkipCredit.clampedMonthDay

    @Suite("SkipCredit.clampedMonthDay")
    struct ClampedMonthDayTests {

        let cal = HabitScheduling.calendar

        @Test("target day within month returns that exact date")
        func withinMonth() {
            let ref = date(year: 2026, month: 3, day: 1)
            let result = SkipCredit.clampedMonthDay(15, inMonthOf: ref, cal: cal)!
            #expect(result == date(year: 2026, month: 3, day: 15))
        }

        @Test("target day 1 always returns the first of the month")
        func firstOfMonth() {
            let ref = date(year: 2026, month: 2, day: 14)
            let result = SkipCredit.clampedMonthDay(1, inMonthOf: ref, cal: cal)!
            #expect(result == date(year: 2026, month: 2, day: 1))
        }

        @Test("target day equals month length returns the last day exactly (no clamping)")
        func exactLastDay() {
            // Feb 2026 has 28 days; requesting day 28 should not clamp.
            let ref = date(year: 2026, month: 2, day: 1)
            let result = SkipCredit.clampedMonthDay(28, inMonthOf: ref, cal: cal)!
            #expect(result == date(year: 2026, month: 2, day: 28))
        }

        @Test("target day 31 in February (28 days) clamps to Feb 28")
        func clampDay31ToFeb28() {
            let ref = date(year: 2026, month: 2, day: 1)
            let result = SkipCredit.clampedMonthDay(31, inMonthOf: ref, cal: cal)!
            #expect(result == date(year: 2026, month: 2, day: 28))
        }

        @Test("target day 30 in February clamps to Feb 28")
        func clampDay30ToFeb28() {
            let ref = date(year: 2026, month: 2, day: 1)
            let result = SkipCredit.clampedMonthDay(30, inMonthOf: ref, cal: cal)!
            #expect(result == date(year: 2026, month: 2, day: 28))
        }

        @Test("target day 29 in non-leap-year February clamps to Feb 28")
        func clampDay29ToFeb28NonLeap() {
            // 2026 is not a leap year.
            let ref = date(year: 2026, month: 2, day: 1)
            let result = SkipCredit.clampedMonthDay(29, inMonthOf: ref, cal: cal)!
            #expect(result == date(year: 2026, month: 2, day: 28))
        }

        @Test("target day 29 in leap-year February returns Feb 29")
        func day29InLeapYearFeb() {
            // 2028 is a leap year.
            let ref = date(year: 2028, month: 2, day: 1)
            let result = SkipCredit.clampedMonthDay(29, inMonthOf: ref, cal: cal)!
            #expect(result == date(year: 2028, month: 2, day: 29))
        }

        @Test("target day 31 in a 31-day month returns the 31st")
        func day31InMarch() {
            let ref = date(year: 2026, month: 3, day: 1)
            let result = SkipCredit.clampedMonthDay(31, inMonthOf: ref, cal: cal)!
            #expect(result == date(year: 2026, month: 3, day: 31))
        }

        @Test("result is always midnight regardless of the reference date's time")
        func resultIsMidnight() {
            let ref = date(year: 2026, month: 5, day: 10, hour: 15, minute: 30)
            let result = SkipCredit.clampedMonthDay(20, inMonthOf: ref, cal: cal)!
            let comps = cal.dateComponents([.hour, .minute, .second], from: result)
            #expect(comps.hour == 0)
            #expect(comps.minute == 0)
            #expect(comps.second == 0)
        }
    }

    // MARK: - weeklyPeriodStart (via SkipCredit.periodStart with a .weekly habit)
    //
    // Calendar reference — March 2026:
    //   Sun 1, Mon 2, Tue 3, Wed 4, Thu 5, Fri 6, Sat 7, Sun 8, Mon 9, ...
    //
    // Algorithm: daysBack = (nowWeekday − anchorWeekday + 7) % 7
    //            periodStart = startOfDay(now) − daysBack days

    @Suite("SkipCredit — weeklyPeriodStart")
    final class WeeklyPeriodStartTests {

        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)
        init() { UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey) }
        deinit { UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey) }

        private func weeklyHabit(anchorWeekday: Int) -> Habit {
            Habit(title: "x", slots: [], skipCreditCount: 0, cycle: .weekly(weekday: anchorWeekday))
        }

        @Test("now is the anchor weekday → period starts today (daysBack = 0)")
        func anchorWeekdayIsToday() {
            // anchor = Thu (weekday 5), now = Thu Mar 5 → daysBack = (5−5+7)%7 = 0 → start = Mar 5
            let thursday = date(year: 2026, month: 3, day: 5)
            let habit = weeklyHabit(anchorWeekday: 5)
            #expect(SkipCredit.periodStart(for: habit, now: thursday) == thursday)
        }

        @Test("anchor weekday falls earlier this week → period started mid-week")
        func anchorWeekdayEarlierThisWeek() {
            // anchor = Mon (weekday 2), now = Thu Mar 5 (weekday 5)
            // daysBack = (5−2+7)%7 = 3 → start = Mar 5 − 3 = Mar 2
            let monday = date(year: 2026, month: 3, day: 2)
            let thursday = date(year: 2026, month: 3, day: 5)
            let habit = weeklyHabit(anchorWeekday: 2)
            #expect(SkipCredit.periodStart(for: habit, now: thursday) == monday)
        }

        @Test("anchor weekday falls later in the week → period started previous week")
        func anchorWeekdayLaterInWeek() {
            // anchor = Fri (weekday 6), now = Thu Mar 5 (weekday 5)
            // daysBack = (5−6+7)%7 = 6 → start = Mar 5 − 6 = Feb 27 (also a Friday)
            let thursday = date(year: 2026, month: 3, day: 5)
            let prevFriday = date(year: 2026, month: 2, day: 27)
            let habit = weeklyHabit(anchorWeekday: 6)
            #expect(SkipCredit.periodStart(for: habit, now: thursday) == prevFriday)
        }

        @Test(
            "now is exactly one week past the anchor weekday → lands on anchor weekday in the same week as now"
        )
        func nowOneWeekPastAnchor() {
            // anchor = Thu (weekday 5), now = Mon Mar 9
            // daysBack = (2−5+7)%7 = 4 → start = Mar 9 − 4 = Mar 5
            let thursday = date(year: 2026, month: 3, day: 5)
            let monday = date(year: 2026, month: 3, day: 9)
            let habit = weeklyHabit(anchorWeekday: 5)
            #expect(SkipCredit.periodStart(for: habit, now: monday) == thursday)
        }

        @Test(
            "anchor on Sunday (weekday 1), now is Saturday (weekday 7) → 6 days back, crosses start of month"
        )
        func anchorSundayNowSaturday() {
            // anchor = Sun (weekday 1), now = Sat Mar 7 (weekday 7)
            // daysBack = (7−1+7)%7 = 6 → start = Mar 7 − 6 = Mar 1
            let sunday = date(year: 2026, month: 3, day: 1)
            let saturday = date(year: 2026, month: 3, day: 7)
            let habit = weeklyHabit(anchorWeekday: 1)
            #expect(SkipCredit.periodStart(for: habit, now: saturday) == sunday)
        }

        @Test("period start rolls back across a month boundary")
        func periodStartCrossesMonthBoundary() {
            // anchor = Sat (weekday 7), now = Fri Mar 6 (weekday 6)
            // daysBack = (6−7+7)%7 = 6 → start = Mar 6 − 6 = Feb 28 (Saturday)
            let friday = date(year: 2026, month: 3, day: 6)
            let prevSaturday = date(year: 2026, month: 2, day: 28)
            let habit = weeklyHabit(anchorWeekday: 7)
            #expect(SkipCredit.periodStart(for: habit, now: friday) == prevSaturday)
        }

        @Test("period end is always exactly 7 days after period start")
        func periodSpanIsSevenDays() {
            let cal = HabitScheduling.calendar
            // anchor = Wed (weekday 4), now = Sat Mar 7
            let now = date(year: 2026, month: 3, day: 7)
            let habit = weeklyHabit(anchorWeekday: 4)
            let start = SkipCredit.periodStart(for: habit, now: now)
            let end = SkipCredit.periodEnd(for: habit, now: now)
            let diff = cal.dateComponents([.day], from: start, to: end).day!
            #expect(diff == 7)
        }
    }

    // MARK: - monthlyPeriodStart (via SkipCredit.periodStart with a .monthly habit)
    //
    // Algorithm:
    //   1. candidate = clampedMonthDay(anchorDay, inMonthOf: today)
    //   2. If candidate ≤ today → return candidate
    //   3. Else → return clampedMonthDay(anchorDay, inMonthOf: prevMonth)

    @Suite("SkipCredit — monthlyPeriodStart")
    final class MonthlyPeriodStartTests {

        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)
        init() { UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey) }
        deinit { UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey) }

        private func monthlyHabit(anchorDay: Int) -> Habit {
            Habit(title: "x", slots: [], skipCreditCount: 0, cycle: .monthly(day: anchorDay))
        }

        @Test("today matches the anchor day → period starts today")
        func anchorDayIsToday() {
            let march5 = date(year: 2026, month: 3, day: 5)
            let habit = monthlyHabit(anchorDay: 5)
            #expect(SkipCredit.periodStart(for: habit, now: march5) == march5)
        }

        @Test("today is past the anchor day → period started earlier this month")
        func anchorDayEarlierThisMonth() {
            // anchor day = 1, today = Mar 5 → candidate Mar 1 ≤ Mar 5 → return Mar 1
            let march1 = date(year: 2026, month: 3, day: 1)
            let march5 = date(year: 2026, month: 3, day: 5)
            let habit = monthlyHabit(anchorDay: 1)
            #expect(SkipCredit.periodStart(for: habit, now: march5) == march1)
        }

        @Test("today is before the anchor day → period started in the previous month")
        func anchorDayLaterInMonth() {
            // anchor day = 20, today = Mar 5 → candidate Mar 20 > Mar 5 → fallback Feb 20
            let march5 = date(year: 2026, month: 3, day: 5)
            let feb20 = date(year: 2026, month: 2, day: 20)
            let habit = monthlyHabit(anchorDay: 20)
            #expect(SkipCredit.periodStart(for: habit, now: march5) == feb20)
        }

        @Test(
            "anchor day 31, today = Feb 15 → candidate clamps to Feb 28 > Feb 15 → fallback Jan 31")
        func anchorDay31TodayFeb15() {
            let feb15 = date(year: 2026, month: 2, day: 15)
            let jan31 = date(year: 2026, month: 1, day: 31)
            let habit = monthlyHabit(anchorDay: 31)
            #expect(SkipCredit.periodStart(for: habit, now: feb15) == jan31)
        }

        @Test("anchor day 31, today = Feb 28 → candidate clamps to Feb 28 ≤ Feb 28 → return Feb 28")
        func anchorDay31TodayFeb28() {
            let feb28 = date(year: 2026, month: 2, day: 28)
            let habit = monthlyHabit(anchorDay: 31)
            #expect(SkipCredit.periodStart(for: habit, now: feb28) == feb28)
        }

        @Test("anchor day 31, today = Mar 15 → candidate Mar 31 > Mar 15 → fallback Feb 28")
        func anchorDay31TodayMar15() {
            let march15 = date(year: 2026, month: 3, day: 15)
            let feb28 = date(year: 2026, month: 2, day: 28)
            let habit = monthlyHabit(anchorDay: 31)
            #expect(SkipCredit.periodStart(for: habit, now: march15) == feb28)
        }

        @Test("anchor day 31, today = Mar 31 → candidate Mar 31 ≤ Mar 31 → return Mar 31")
        func anchorDay31TodayMar31() {
            let march31 = date(year: 2026, month: 3, day: 31)
            let habit = monthlyHabit(anchorDay: 31)
            #expect(SkipCredit.periodStart(for: habit, now: march31) == march31)
        }

        @Test(
            "crosses year boundary: anchor day 15, today = Jan 10 → period started Dec 15 last year"
        )
        func crossesYearBoundary() {
            // anchor day = 15, today Jan 10 → candidate Jan 15 > Jan 10 → fallback Dec 15 2025
            let dec15 = date(year: 2025, month: 12, day: 15)
            let jan10 = date(year: 2026, month: 1, day: 10)
            let habit = monthlyHabit(anchorDay: 15)
            #expect(SkipCredit.periodStart(for: habit, now: jan10) == dec15)
        }
    }

    // MARK: - nextMonthlyPeriodStart (via SkipCredit.periodEnd with a .monthly habit)
    //
    // Algorithm: advance currentPeriodStart by 1 calendar month, then clampedMonthDay.
    // periodEnd(for:now:) = nextMonthlyPeriodStart(anchorDay: habit.cycle.day, after: periodStart)

    @Suite("SkipCredit — nextMonthlyPeriodStart")
    final class NextMonthlyPeriodStartTests {

        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)
        init() { UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey) }
        deinit { UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey) }

        private func monthlyHabit(anchorDay: Int) -> Habit {
            Habit(title: "x", slots: [], skipCreditCount: 0, cycle: .monthly(day: anchorDay))
        }

        @Test("normal month: next period starts on the same day-of-month one month later")
        func normalMonthAdvancesOneMonth() {
            // anchor day = 15, now = Mar 20 → periodStart = Mar 15 → next = Apr 15
            let march20 = date(year: 2026, month: 3, day: 20)
            let apr15 = date(year: 2026, month: 4, day: 15)
            let habit = monthlyHabit(anchorDay: 15)
            #expect(SkipCredit.periodEnd(for: habit, now: march20) == apr15)
        }

        @Test("anchor day 31, period started Jan 31 → next period start = Feb 28 (clamped)")
        func nextFromJan31IsClampedToFeb28() {
            // nextMonth of Jan 31 = Feb 28 (calendar arithmetic); clampedMonthDay(31, Feb) = Feb 28
            let jan31 = date(year: 2026, month: 1, day: 31)
            let feb28 = date(year: 2026, month: 2, day: 28)
            let habit = monthlyHabit(anchorDay: 31)
            #expect(SkipCredit.periodEnd(for: habit, now: jan31) == feb28)
        }

        @Test("anchor day 31, period started Feb 28 → next period start = Mar 31")
        func nextFromFeb28IsMar31() {
            // periodStart for anchorDay=31, now=Feb28 → Feb 28 (clamp); next = Mar 31
            let feb28 = date(year: 2026, month: 2, day: 28)
            let march31 = date(year: 2026, month: 3, day: 31)
            let habit = monthlyHabit(anchorDay: 31)
            #expect(SkipCredit.periodEnd(for: habit, now: feb28) == march31)
        }

        @Test("crosses year boundary: period started Dec 10 → next start = Jan 10")
        func nextPeriodCrossesYearBoundary() {
            let dec15 = date(year: 2025, month: 12, day: 15)
            let jan10 = date(year: 2026, month: 1, day: 10)
            let habit = monthlyHabit(anchorDay: 10)
            #expect(SkipCredit.periodEnd(for: habit, now: dec15) == jan10)
        }

        @Test("period end is always strictly after period start")
        func periodEndIsAfterPeriodStart() {
            let now = date(year: 2026, month: 3, day: 10)
            let habit = monthlyHabit(anchorDay: 5)
            let start = SkipCredit.periodStart(for: habit, now: now)
            let end = SkipCredit.periodEnd(for: habit, now: now)
            #expect(end > start)
        }
    }
}
