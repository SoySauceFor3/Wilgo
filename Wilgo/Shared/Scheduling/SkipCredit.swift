import Foundation

/// Pure logic for computing skip-credit state for a commitment.
enum SkipCredit {
    /// A credit is burned for each psychological day in the period where
    /// the commitment was not fully completed (completions < slots.count).
    /// PsychDay is inclusive end date if inclusive is true, otherwise exclusive end date.
    /// NOTE: the current implementation allows extra check-ins beyond the goalCountPerDay to be used as skip credits.
    static func creditsUsedInCycle(
        for commitment: Commitment, until psychDay: Date, inclusive: Bool = true
    )
        -> Int
    {
        let cal = CommitmentScheduling.calendar
        let start = commitment.cycle.start(of: psychDay)

        var burned = 0
        var day = start
        while (inclusive && day <= psychDay) || (!inclusive && day < psychDay) {
            burned += commitment.goalCountPerDay - commitment.completedCount(for: day)

            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return max(0, burned)
    }

    /// Credits still available in the cycle of PsychDay, inclusively.
    static func creditsRemaining(
        for commitment: Commitment, until psychDay: Date, inclusive: Bool = false
    )
        -> Int
    {
        max(
            0,
            commitment.skipCreditCount
                - creditsUsedInCycle(for: commitment, until: psychDay, inclusive: inclusive))
    }

    // MARK: - Display

    /// Compact one-line summary for a commitment that was not fully completed on `psychDay`.
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
    static func notificationLine(for commitment: Commitment, on psychDay: Date) -> String {
        let completed = commitment.completedCount(for: psychDay)
        let required = commitment.goalCountPerDay
        let used = creditsUsedInCycle(for: commitment, until: psychDay)
        let allowance = commitment.skipCreditCount

        let icon = completed == 0 ? "❌" : "⚠️"

        var line =
            "\(icon) \(commitment.title) — \(completed)/\(required) checkIns · \(used)/\(allowance)cr used"
        if used > allowance, let punishment = commitment.punishment {
            line += " · \(punishment)"
        }
        return line
    }
}
