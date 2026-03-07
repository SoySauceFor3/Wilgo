import Foundation

/// Pure logic for computing skip-credit state for a habit.
enum SkipCredit {
    /// A credit is burned for each psychological day in the period where
    /// the habit was not fully completed (completions < slots.count).
    /// PsychDay is inclusive end date.
    static func creditsUsedInCycle(for habit: Habit, until psychDay: Date) -> Int {
        let cal = HabitScheduling.calendar
        let start = habit.cycle.start(of: psychDay)

        var burned = 0
        var day = start
        while day <= psychDay {
            burned += habit.unfinishedSlots(for: day).count

            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return burned
    }

    /// Credits still available in the cycle of PsychDay, inclusively.
    static func creditsRemaining(for habit: Habit, until psychDay: Date) -> Int {
        max(0, habit.skipCreditCount - creditsUsedInCycle(for: habit, until: psychDay))
    }

    // MARK: - Display

    /// Compact one-line summary for a habit that was not fully completed on `psychDay`.
    ///
    /// Format: `<icon> <title> — <done>/<required> · <used>/<allowance>cr <delta>[· <punishment>]`
    ///
    /// - `❌` when nothing was completed; `⚠️` when partially completed.
    /// - Delta is `+N` (N credits left) or `−N` (N over budget).
    /// - Punishment appended only when credits are exhausted and a punishment is set.
    ///
    /// Example outputs:
    /// ```
    /// ❌ Exercise — 0/2 · 5/4cr −1 · Give robaroba 20 RMB
    /// ⚠️ Reading — 1/2 · 2/3cr +1
    /// ```
    static func notificationLine(for habit: Habit, on psychDay: Date) -> String {
        let completed = habit.completedCount(for: psychDay)
        let required  = habit.slots.count
        let used      = creditsUsedInCycle(for: habit, until: psychDay)
        let allowance = habit.skipCreditCount
        let remaining = creditsRemaining(for: habit, until: psychDay)

        let icon  = completed == 0 ? "❌" : "⚠️"
        let delta = used > allowance ? "−\(used - allowance)" : "+\(remaining)"

        var line = "\(icon) \(habit.title) — \(completed)/\(required) · \(used)/\(allowance)cr \(delta)"
        if remaining == 0, let punishment = habit.punishment {
            line += " · \(punishment)"
        }
        return line
    }
}
