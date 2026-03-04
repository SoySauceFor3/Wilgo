import Foundation

/// Pure logic for computing skip-credit state for a habit.
/// No UI, no SwiftData writes — just reads the model and does math.
enum SkipCreditService {

    // MARK: - Period Boundaries

    /// Start of the current budget period (week/month start from natural calendar boundary).
    static func periodStart(for period: Period, now: Date = .now) -> Date {
        let cal = HabitScheduling.calendar
        switch period {
        case .daily:
            return cal.startOfDay(for: now)
        case .weekly:
            // Locale-aware natural week start (Sunday in US, Monday elsewhere).
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            return cal.date(from: comps) ?? cal.startOfDay(for: now)
        case .monthly:
            let comps = cal.dateComponents([.year, .month], from: now)
            return cal.date(from: comps) ?? cal.startOfDay(for: now)
        }
    }

    /// Exclusive end of the current budget period.
    static func periodEnd(for period: Period, now: Date = .now) -> Date {
        let cal = HabitScheduling.calendar
        let start = periodStart(for: period, now: now)
        switch period {
        case .daily: return cal.date(byAdding: .day, value: 1, to: start) ?? start
        case .weekly: return cal.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
        case .monthly: return cal.date(byAdding: .month, value: 1, to: start) ?? start
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
        let start = periodStart(for: habit.skipCreditPeriod, now: now)
        let today = HabitScheduling.todayPsychDay(now: now)

        var burned = 0
        var day = start
        while day < today {
            let completions = habit.checkIns.filter { $0.pyschDay == day }.count
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
    /// Daily → "Mar 4", Weekly → "This Week", Monthly → "March".
    static func periodLabel(for period: Period, now: Date = .now) -> String {
        let fmt = DateFormatter()
        switch period {
        case .daily:
            fmt.dateFormat = "MMM d"
            return fmt.string(from: now)
        case .weekly:
            let cal = HabitScheduling.calendar
            let weekday = cal.component(.weekday, from: now)
            let daysFromMonday = (weekday + 5) % 7
            let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: cal.startOfDay(for: now)) ?? now
            fmt.dateFormat = "MMM d"
            return "Week of \(fmt.string(from: monday))"
        case .monthly:
            fmt.dateFormat = "MMMM"
            return fmt.string(from: now)
        }
    }
}
