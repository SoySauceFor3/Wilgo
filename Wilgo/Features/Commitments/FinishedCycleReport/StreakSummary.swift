import Foundation

/// Computes a short contextual streak line shown on a failed cycle card in the FCR.
///
/// Source of truth is check-in data against cycle boundaries — independent of
/// CycleRecord, so cycle-setting changes never corrupt the count.
enum StreakSummary {
    enum Outcome {
        case passed
        case failed
    }

    /// How many cycles of history to look back over (including the current one).
    static let lookbackWindow = 12

    /// Pure priority logic. `recentOutcomes` is most-recent-first; index 0 is the
    /// cycle being reported (always `.failed`).
    static func summarize(recentOutcomes: [Outcome]) -> String? {
        guard let first = recentOutcomes.first, first == .failed else { return nil }

        // Case 1: 2+ consecutive failures from the current cycle backward.
        let leadingFailures = recentOutcomes.prefix(while: { $0 == .failed }).count
        if leadingFailures >= 2 {
            return "\(leadingFailures) consecutive failed cycles"
        }

        // Exactly one trailing failure (leadingFailures == 1 here).
        let afterFailure = recentOutcomes.dropFirst()
        let winStreak = afterFailure.prefix(while: { $0 == .passed }).count
        let totalFailures = recentOutcomes.count(where: { $0 == .failed })

        // Case 3: a single-cycle win gap with multiple failures in the window is
        // a flaky on-off pattern — report the honest ratio rather than understate
        // it as "first failure after 1 win".
        if winStreak == 1, totalFailures >= 2 {
            return "Failed \(totalFailures) of the last \(recentOutcomes.count) cycles"
        }

        // Case 2: a genuine slip after a real run of wins (or a lone first slip).
        if winStreak >= 1 {
            let unit = winStreak == 1 ? "win" : "wins"
            return "First failure after \(winStreak) consecutive \(unit)"
        }

        // Single failure with no prior context.
        return nil
    }

    /// Walks real cycles backward from `beforeCycleEnd` for `commitment`,
    /// classifying each by check-in count vs target, then delegates to `summarize`.
    static func compute(for commitment: Commitment, currentCycleEnd: Date) -> String? {
        var outcomes: [Outcome] = []
        let cycle = commitment.cycle
        let target = commitment.target.count

        // Start with the cycle whose end is `currentCycleEnd` and walk back,
        // stopping once we reach cycles that begin before the commitment existed.
        var cursorCycleEnd = currentCycleEnd
        for _ in 0..<lookbackWindow {
            let labelDay = previousPsychDay(cursorCycleEnd)
            let cycleStart = cycle.startDayOfCycle(including: labelDay)

            let count = commitment.checkInsInRange(
                startPsychDay: cycleStart,
                endPsychDay: cursorCycleEnd
            ).count
            outcomes.append(count >= target ? .passed : .failed)

            // The previous cycle ends where this one starts.
            if cycleStart <= cycle.anchorPsychDay { break }
            cursorCycleEnd = cycleStart
        }

        return summarize(recentOutcomes: outcomes)
    }

    private static func previousPsychDay(_ date: Date) -> Date {
        Time.calendar.date(byAdding: .day, value: -1, to: date) ?? date
    }
}
