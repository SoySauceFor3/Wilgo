import Foundation

/// Pure logic for computing skip-credit state for a habit.
/// No UI, no SwiftData writes — just reads the model and does math.
enum SkipCredit {

    // MARK: - Period Boundaries

    /// Start of the current budget period, derived from `habit.cycle`.
    ///
    /// - `.daily`:           start of today (midnight).
    /// - `.weekly(weekday)`: most recent occurrence of that weekday on or before `now`.
    /// - `.monthly(day)`:    most recent occurrence of that day-of-month on or before `now`,
    ///   clamped to the last day of shorter months (e.g. day=31 → Feb 28/29).
    static func periodStart(for habit: Habit, now: Date = HabitScheduling.now()) -> Date {
        switch habit.cycle {
        case .daily:
            return HabitScheduling.calendar.startOfDay(for: now)
        case .weekly(let weekday):
            return weeklyPeriodStart(anchorWeekday: weekday, now: now)
        case .monthly(let day):
            return monthlyPeriodStart(anchorDay: day, now: now)
        }
    }

    /// Exclusive end of the current budget period.
    static func periodEnd(for habit: Habit, now: Date = .now) -> Date {
        let cal = HabitScheduling.calendar
        let start = periodStart(for: habit, now: now)
        switch habit.cycle {
        case .daily:   return cal.date(byAdding: .day, value: 1, to: start) ?? start
        case .weekly:  return cal.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
        case .monthly(let day): return nextMonthlyPeriodStart(anchorDay: day, after: start)
        }
    }

    // MARK: - Credit Accounting

    /// Credits burned so far in the current period.
    ///
    /// A credit is burned for each **past** psychological day in the period where
    /// the habit was not fully completed (completions < slots.count).
    /// Today is excluded — it hasn't ended yet.
    static func creditsUsed(for habit: Habit, now: Date = .now) -> Int {
        let cal = HabitScheduling.calendar
        let start = periodStart(for: habit, now: now)
        let today = HabitScheduling.psychDay(for: now)

        var burned = 0
        var day = start
        while day < today {
            let completions = habit.checkIns.filter { $0.psychDay == day }.count
            burned += max(0, habit.slots.count - completions)

            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return burned
    }

    /// Credits still available in the current period (floor of 0).
    static func creditsRemaining(for habit: Habit, now: Date = .now) -> Int {
        max(0, habit.skipCreditCount - creditsUsed(for: habit, now: now))
    }

    /// True when credits are exhausted AND a punishment string has been set.
    static func isInPunishment(for habit: Habit, now: Date = .now) -> Bool {
        habit.punishment != nil && creditsUsed(for: habit, now: now) >= habit.skipCreditCount
    }

    // MARK: - Display Helpers

    /// Human-readable period label.
    /// Daily → "Mar 4", Weekly → "Week of Mar 2", Monthly → "March".
    static func periodLabel(for habit: Habit, now: Date = .now) -> String {
        let fmt = DateFormatter()
        let start = periodStart(for: habit, now: now)
        switch habit.cycle.kind {
        case .daily:
            fmt.dateFormat = "MMM d"
            return fmt.string(from: now)
        case .weekly:
            fmt.dateFormat = "MMM d"
            return "Week of \(fmt.string(from: start))"
        case .monthly:
            fmt.dateFormat = "MMMM"
            return fmt.string(from: start)
        }
    }

    // MARK: - Private: Anchor-based period math

    /// Most recent date on or before `now` whose weekday matches `anchorWeekday` (1 = Sun … 7 = Sat).
    private static func weeklyPeriodStart(anchorWeekday: Int, now: Date) -> Date {
        let cal = HabitScheduling.calendar
        let nowWeekday = cal.component(.weekday, from: cal.startOfDay(for: now))
        let daysBack = (nowWeekday - anchorWeekday + 7) % 7
        return cal.date(byAdding: .day, value: -daysBack, to: cal.startOfDay(for: now))
            ?? cal.startOfDay(for: now)
    }

    /// Most recent date on or before `now` whose day-of-month matches `anchorDay` (1–31),
    /// clamped to the last day of the relevant month.
    private static func monthlyPeriodStart(anchorDay: Int, now: Date) -> Date {
        let cal = HabitScheduling.calendar
        let today = cal.startOfDay(for: now)

        // Try this calendar month first.
        if let candidate = clampedMonthDay(anchorDay, inMonthOf: today, cal: cal),
            cal.compare(candidate, to: today, toGranularity: .day) != .orderedDescending
        {
            return candidate
        }

        // Fall back to the previous calendar month.
        let prevMonth = cal.date(byAdding: .month, value: -1, to: today) ?? today
        return clampedMonthDay(anchorDay, inMonthOf: prevMonth, cal: cal)
            ?? cal.startOfDay(for: prevMonth)
    }

    /// Returns the date for day `targetDay` in the same month as `reference`, clamped to
    /// the last day of that month if `targetDay` exceeds the month's length.
    /// Returns `nil` only if calendar arithmetic fails entirely.
    static func clampedMonthDay(_ targetDay: Int, inMonthOf reference: Date, cal: Calendar) -> Date?
    {
        guard let range = cal.range(of: .day, in: .month, for: reference) else { return nil }
        let day = min(targetDay, range.count)
        var comps = cal.dateComponents([.year, .month], from: reference)
        comps.day = day
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return cal.date(from: comps)
    }

    /// Start of the monthly period that immediately follows `currentPeriodStart`.
    private static func nextMonthlyPeriodStart(anchorDay: Int, after currentPeriodStart: Date)
        -> Date
    {
        let cal = HabitScheduling.calendar
        let nextMonth =
            cal.date(byAdding: .month, value: 1, to: currentPeriodStart) ?? currentPeriodStart
        return clampedMonthDay(anchorDay, inMonthOf: nextMonth, cal: cal) ?? nextMonth
    }
}
