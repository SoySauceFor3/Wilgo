import Foundation

// TODO: THIS NEED TO CHANGED!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! It only supports daily cycle for target.

/// Pure logic for computing skip-credit state for a commitment.
enum SkipCredit {
    /// NOTE:
    /// 1. we allow extra check-ins to be used as skip credits.
    /// 2. The assumption here is that the skipBudget cycle is definitely consist of multiple of target cycles,
    /// no gap between the two cycles (e.g. weekly target start on Monday, but weekly skipBudget start on Sunday)
    /// 3. here the `inclusive` means do we count the target cycle of psychDay.
    static func creditsUsedInCycle(
        for commitment: Commitment, until psychDay: Date, inclusive: Bool = true
    )
        -> Int
    {
        let calendar = Time.calendar
        let targetCycle = commitment.target.cycle
        let skipCycle = commitment.skipBudget.cycle

        // If there is no requirement per target cycle, no credits can be burned.
        if commitment.target.count <= 0 {
            return 0
        }

        // Start of the skip-budget period that contains `psychDay`.
        let skipStart = skipCycle.startDayOfCycle(including: psychDay)

        // Determine the exclusive upper bound for iterating target cycles inside
        // this skip-budget period.
        //
        // - inclusive == true  → include the target cycle that contains `psychDay`
        //   (i.e. iterate up to that cycle’s exclusive end).
        // - inclusive == false → only include target cycles strictly before the
        //   one that contains `psychDay` (i.e. end at that cycle’s start).
        let targetCycleStartForPsych = targetCycle.startDayOfCycle(including: psychDay)
        let endExclusive: Date = {
            if inclusive {
                return targetCycle.endDayOfCycle(including: psychDay)
            } else {
                return targetCycleStartForPsych
            }
        }()

        // Find the first target-cycle start that is within the skip-budget period.
        var currentTargetStart = targetCycle.startDayOfCycle(including: skipStart)
        if currentTargetStart != skipStart {
            fatalError(
                "Target cycle start does not align with skip cycle start. This should not happen.")
        }
        // // Move forward until we are on/after the skip period start.
        // while currentTargetStart < skipStart {
        //     let next = targetCycle.endDayOfCycle(including: currentTargetStart)
        //     // Guard against non-advancing calendars, though this shouldn't happen.
        //     if next <= currentTargetStart { break }
        //     currentTargetStart = next
        // }

        // If the first relevant target cycle already falls beyond our upper bound,
        // there is nothing to count yet.
        if currentTargetStart >= endExclusive {
            return 0
        }

        // Iterate over target cycles fully contained in [skipStart, endExclusive),
        // counting how many such cycles there are and what the combined time
        // window is. Extra check-ins in earlier target cycles can offset misses
        // in later ones, so we accumulate over the whole window.
        let unionStart = currentTargetStart
        var unionEndExclusive = unionStart
        var targetCycleCount = 0

        while currentTargetStart < endExclusive {
            let nextTargetCycleStart = targetCycle.endDayOfCycle(including: currentTargetStart)
            if nextTargetCycleStart <= currentTargetStart {
                break  // safety against infinite loops
            }

            targetCycleCount += 1
            if nextTargetCycleStart > unionEndExclusive {
                unionEndExclusive = nextTargetCycleStart
            }

            currentTargetStart = nextTargetCycleStart
        }

        // Sanity check: if no cycles were found, no credits used.
        if targetCycleCount == 0 || unionEndExclusive <= unionStart {
            return 0
        }

        // Count all check-ins whose psychological day falls within the combined
        // window of these target cycles.
        let completedTotal = commitment.checkIns.filter {
            let day = calendar.startOfDay(for: $0.psychDay)
            return unionStart <= day && day < unionEndExclusive
        }.count

        let requiredTotal = targetCycleCount * commitment.target.count
        return max(0, requiredTotal - completedTotal)
    }

    /// Credits still available in the cycle of PsychDay, inclusively.
    static func creditsRemaining(
        for commitment: Commitment, until psychDay: Date, inclusive: Bool = false
    )
        -> Int
    {
        max(
            0,
            commitment.skipBudget.count
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
        let required = commitment.target.count
        let used = creditsUsedInCycle(for: commitment, until: psychDay)
        let allowance = commitment.skipBudget.count

        let icon = completed == 0 ? "❌" : "⚠️"

        var line =
            "\(icon) \(commitment.title) — \(completed)/\(required) checkIns · \(used)/\(allowance)cr used"
        if used > allowance, let punishment = commitment.punishment {
            line += " · \(punishment)"
        }
        return line
    }
}
