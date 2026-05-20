import Foundation

/// Pure logic for applying a week-start change to existing weekly commitments.
enum WeekStartChangeHandler {
    /// Commitments whose cycle anchor will shift when `newStartsOnMonday` is applied.
    /// Returns only weekly commitments whose current anchor weekday doesn't match the new setting.
    static func affectedCommitments(
        _ commitments: [Commitment],
        newStartsOnMonday: Bool
    ) -> [Commitment] {
        let targetWeekday = newStartsOnMonday ? 2 : 1
        let cal = Time.calendar
        return commitments.filter { c in
            guard c.cycle.kind == .weekly else { return false }
            let currentAnchorWeekday = cal.component(.weekday, from: c.cycle.anchorPsychDay)
            return currentAnchorWeekday != targetWeekday
        }
    }

    private static func cycleBoundaries(weekday: Int, today: Date) -> (start: Date, end: Date) {
        let cal = Time.calendar
        let currWeekday = cal.component(.weekday, from: cal.startOfDay(for: today))
        let daysBack = (currWeekday - weekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -daysBack, to: cal.startOfDay(for: today))
            ?? cal.startOfDay(for: today)
        let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
        return (start, end)
    }

    private static func newCurrentCycleBoundaries(
        newStartsOnMonday: Bool, today: Date
    ) -> (start: Date, end: Date) {
        cycleBoundaries(weekday: newStartsOnMonday ? 2 : 1, today: today)
    }

    /// The start of the current cycle under the *new* week-start boundary (on or before today).
    static func newCurrentCycleStart(newStartsOnMonday: Bool, today: Date = Time.now()) -> Date {
        newCurrentCycleBoundaries(newStartsOnMonday: newStartsOnMonday, today: today).start
    }

    /// The exclusive end of the current cycle under the new week-start boundary.
    static func newCurrentCycleEnd(newStartsOnMonday: Bool, today: Date = Time.now()) -> Date {
        newCurrentCycleBoundaries(newStartsOnMonday: newStartsOnMonday, today: today).end
    }

    /// Applies the week-start change to `commitments`:
    /// 1. Re-anchors each commitment's cycle to the new week-start boundary.
    /// 2. If `makeCurrentCycleInspirationOnly` is true, marks the current cycle inspiration-only.
    static func apply(
        to commitments: [Commitment],
        newStartsOnMonday: Bool,
        makeCurrentCycleInspirationOnly: Bool,
        today: Date = Time.now()
    ) {
        let (cycleStart, cycleEnd) = newCurrentCycleBoundaries(newStartsOnMonday: newStartsOnMonday, today: today)

        for commitment in commitments {
            // Re-anchor to the new week-start. Preserves multiplier, but note:
            // multiplier > 1 is unused — re-anchoring a multi-week block is ambiguous.
            commitment.cycle = Cycle(
                kind: .weekly,
                referencePsychDay: cycleStart,
                multiplier: commitment.cycle.multiplier
            )
            if makeCurrentCycleInspirationOnly {
                commitment.target.setConfiguredMode(
                    .inspirationOnly(start: cycleStart, until: cycleEnd)
                )
            }
        }
    }
}
