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

    /// The start of the current cycle under the *new* week-start boundary (on or before today).
    /// Temporarily sets the UserDefaults key to `newStartsOnMonday` so Cycle.makeDefault picks it up,
    /// then restores the original value.
    static func newCurrentCycleStart(newStartsOnMonday: Bool, today: Date = Time.now()) -> Date {
        let previous = UserDefaults.standard.object(forKey: AppSettings.weekStartsOnMondayKey)
        UserDefaults.standard.set(newStartsOnMonday, forKey: AppSettings.weekStartsOnMondayKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: AppSettings.weekStartsOnMondayKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey)
            }
        }
        let cycle = Cycle.makeDefault(.weekly, on: today)
        return cycle.startDayOfCycle(including: today)
    }

    /// The exclusive end of the current cycle under the new week-start boundary.
    static func newCurrentCycleEnd(newStartsOnMonday: Bool, today: Date = Time.now()) -> Date {
        let previous = UserDefaults.standard.object(forKey: AppSettings.weekStartsOnMondayKey)
        UserDefaults.standard.set(newStartsOnMonday, forKey: AppSettings.weekStartsOnMondayKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: AppSettings.weekStartsOnMondayKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey)
            }
        }
        let cycle = Cycle.makeDefault(.weekly, on: today)
        return cycle.endDayOfCycle(including: today)
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
        let cycleStart = newCurrentCycleStart(newStartsOnMonday: newStartsOnMonday, today: today)
        let cycleEnd = newCurrentCycleEnd(newStartsOnMonday: newStartsOnMonday, today: today)

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
