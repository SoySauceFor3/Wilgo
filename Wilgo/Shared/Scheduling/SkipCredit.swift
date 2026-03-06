import Foundation

// MARK: - Skip credit accounting

/// Pure logic for computing skip-credit state for a habit.
/// No UI, no SwiftData writes — just reads the model and does math.
enum SkipCredit {

    // MARK: - Credit Accounting

    /// Credits burned so far in the current period.
    ///
    /// A credit is burned for each **past** psychological day in the period where
    /// the habit was not fully completed (completions < slots.count).
    /// Today is excluded — it hasn't ended yet.
    static func creditsUsed(for habit: Habit, now: Date = HabitScheduling.now()) -> Int {
        let cal = HabitScheduling.calendar
        let start = habit.cycle.start()
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
    static func creditsRemaining(for habit: Habit, now: Date = HabitScheduling.now()) -> Int {
        max(0, habit.skipCreditCount - creditsUsed(for: habit, now: now))
    }

    /// True when credits are exhausted AND a punishment string has been set.
    static func isInPunishment(for habit: Habit, now: Date = HabitScheduling.now()) -> Bool {
        habit.punishment != nil && creditsUsed(for: habit, now: now) >= habit.skipCreditCount
    }


}
