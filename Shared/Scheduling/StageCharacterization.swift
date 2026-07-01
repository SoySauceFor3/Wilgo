import Foundation

enum StageCharacterization {
    /// Characterizes a single commitment at `now`. Computed uniformly for every commitment the caller
    /// passes (callers pass the `isActiveForReminders`-filtered set, so the goal-met/continue rule is
    /// applied once at the boundary). `nearestUsable` is computed for all — including current-slot
    /// commitments — for one uniform code path.
    static func characteristics(of commitment: Commitment, now: Date = Time.now())
        -> CommitmentCharacteristics
    {
        // Unfinished, unsnoozed, unsaturated occurrences remaining in the current cycle.
        let remaining = commitment.remainingUsableOccurrencesInCycle(now: now)
        // The open-now slot is the first remaining occurrence that has already started.
        let currentOccurrence: SlotOccurrence? = {
            guard let first = remaining.first, first.start <= now else { return nil }
            return first
        }()
        // behindCount: goal still needs this many check-ins that no remaining in-cycle slot covers.
        // Nil leftToDo (target disabled) → not behind.
        let behindCount = commitment.goalProgress(now: now).leftToDo
            .map { max(0, $0 - remaining.count) } ?? 0

        let nearest = commitment.nearestUsableUpcomingOccurrence(now: now)
        let nearestUsableInCurrentCycle: Bool = nearest.map {
            let bounds = commitment.cycle.bounds(including: now)
            return $0.start >= bounds.start && $0.start < bounds.end
        } ?? false
        return CommitmentCharacteristics(
            commitment: commitment,
            currentOccurrence: currentOccurrence,
            remainingThisCycleCount: remaining.count,
            nearestUsable: nearest,
            nearestUsableInCurrentCycle: nearestUsableInCurrentCycle,
            behindCount: behindCount,
            checkInCount: commitment.checkInsInCycle(containing: now).count,
            targetCount: commitment.target.count
        )
    }

    /// The combined Stage buckets, placed from pre-built `characteristics` (one per active commitment —
    /// callers build them once, e.g. so the same pass also feeds `behindForReminder`). Implements the
    /// closest-N Upcoming rule and the Upcoming-takes-priority / overflow-demotes-to-Catch-up rule.
    ///
    /// - **Current**: an open slot right now (`isCurrent`).
    /// - **Upcoming**: the `n` non-current commitments whose nearest usable slot is soonest (ranked
    ///   across commitments, capped at `n`).
    /// - **Catch-up**: behind commitments *not* in Upcoming — those with no usable upcoming slot, plus
    ///   behind ones whose nearest slot fell outside the top-`n` (overflow demotion).
    ///
    /// A commitment appears in exactly one bucket. `n` counts commitments, not slots. The active /
    /// goal-met filter is applied by the caller when building `characteristics`.
    static func stageBuckets(
        characteristics: [CommitmentCharacteristics],
        now: Date,
        n: Int
    ) -> (
        current: [CommitmentCharacteristics],
        upcoming: [CommitmentCharacteristics],
        catchUp: [CommitmentCharacteristics]
    ) {
        // Current: open slot right now, sorted by remaining fraction of the open slot (sooner-to-end first).
        let current =
            characteristics
            .filter(\.isCurrent)
            .sorted {
                ($0.currentOccurrence?.remainingFraction(at: now) ?? 1)
                    < ($1.currentOccurrence?.remainingFraction(at: now) ?? 1)
            }
        let currentIDs = Set(current.map(\.commitment.id))

        // Future-eligible: non-current, with a nearest usable slot. Rank by that slot's start (then end).
        let futureEligible =
            characteristics
            .filter { !currentIDs.contains($0.commitment.id) && $0.nearestUsable != nil }
            .sorted {
                // Safe to force-unwrap: filtered to non-nil nearestUsable above.
                let lhs = $0.nearestUsable!
                let rhs = $1.nearestUsable!
                if lhs.start == rhs.start { return lhs.end < rhs.end }
                return lhs.start < rhs.start
            }

        let upcoming = Array(futureEligible.prefix(max(0, n)))
        let excluded = currentIDs.union(upcoming.map(\.commitment.id))

        // Catch-up: behind and not in Current/Upcoming. Covers "no upcoming slot" + overflow demotion.
        let catchUp =
            characteristics
            .filter { $0.isBehind && !excluded.contains($0.commitment.id) }
            .sorted(by: Self.catchUpUrgencyOrder)

        return (current: current, upcoming: upcoming, catchUp: catchUp)
    }

    /// Convenience that runs the full Stage pass from raw commitments: filter to
    /// `isActiveForReminders`, `characteristics(of:)` each, then `stageBuckets(...)`. Used by
    /// `StageView`, which recomputes this directly in `body` (the work is cheap enough that caching
    /// it is not worth the machinery).
    static func stageBuckets(
        commitments: [Commitment],
        now: Date = Time.now(),
        n: Int = AppSettings.upcomingCommitmentCount
    ) -> (
        current: [CommitmentCharacteristics],
        upcoming: [CommitmentCharacteristics],
        catchUp: [CommitmentCharacteristics]
    ) {
        let all =
            commitments
            .filter { $0.isActiveForReminders(now: now) }
            .map { characteristics(of: $0, now: now) }
        return stageBuckets(characteristics: all, now: now, n: n)
    }

    /// Commitments that should fire a catch-up reminder: every behind commitment, regardless of which
    /// Stage bucket it lands in (so a behind one sitting in Upcoming's top-N is still reminded).
    ///
    /// When `includeCurrent` is false (the default), commitments currently in an **open slot** are
    /// excluded — they're already maximally visible (Stage row + Live Activity) and the user is in the
    /// window to act, so a push notification would be redundant. The caller passes the user's setting.
    static func behindForReminder(
        characteristics: [CommitmentCharacteristics],
        includeCurrent: Bool = false
    ) -> [CommitmentCharacteristics] {
        characteristics.filter { $0.isBehind && (includeCurrent || !$0.isCurrent) }
    }

    /// Catch-up urgency ordering: by `behindCount / targetCount` (higher first), then larger target
    /// count, then earliest next usable slot. A stored closure (not a method) so it stays nonisolated
    /// and is usable from both `@MainActor` and non-isolated callers (e.g. the widget timeline).
    private static let catchUpUrgencyOrder:
        (CommitmentCharacteristics, CommitmentCharacteristics) -> Bool = { lhs, rhs in
            let lhsTargetCount = max(lhs.commitment.target.count, 1)
            let rhsTargetCount = max(rhs.commitment.target.count, 1)
            let lhsUrgency = Double(lhs.behindCount) / Double(lhsTargetCount)
            let rhsUrgency = Double(rhs.behindCount) / Double(rhsTargetCount)
            if lhsUrgency != rhsUrgency { return lhsUrgency > rhsUrgency }
            if lhs.commitment.target.count != rhs.commitment.target.count {
                return lhs.commitment.target.count > rhs.commitment.target.count
            }
            guard let lhsSlot = lhs.nearestUsable, let rhsSlot = rhs.nearestUsable else {
                if lhs.nearestUsable == nil, rhs.nearestUsable != nil { return false }
                if lhs.nearestUsable != nil, rhs.nearestUsable == nil { return true }
                return false
            }
            if lhsSlot.start == rhsSlot.start { return lhsSlot.end < rhsSlot.end }
            return lhsSlot.start < rhsSlot.start
        }

    /// Earliest upcoming slot-window edge (an occurrence `start` or `end`) across all commitments'
    /// slots, or `nil` when no commitment has a future slot edge. Recurrence-aware and
    /// usability-agnostic (a window edge is a transition regardless of snooze/saturation).
    ///
    /// Intentionally does NOT apply `isActiveForReminders`: a goal-met commitment can become
    /// un-met across a cycle boundary, and waking slightly early is harmless — whereas filtering
    /// here could skip a needed wake-up. This is the one helper that does not gate on that rule.
    ///
    /// This reports *slot* transitions only. It deliberately does NOT include the cycle-boundary wake
    /// (a goal-met commitment reappears when its cycle rolls over, with no slot edge at that instant).
    /// Callers that render the Stage want that too — so they should call `nextStageRefreshTime`, which
    /// folds this together with the cycle boundary. This primitive is exposed for callers that truly
    /// only care about slot windows.
    static func nextTransitionTime(
        commitments: [Commitment], now: Date = Time.now()
    ) -> Date? {
        commitments.compactMap { $0.nextSlotWindowEdge(after: now) }.min()
    }

    /// The next instant the Stage's *rendered content* can change: the earlier of the next slot-window
    /// edge (`nextTransitionTime`) and the next cycle boundary. Always a `Date` — the next-psychDay
    /// boundary is a floor that is present whether or not any slot transition exists, so callers never
    /// have to invent their own "nothing scheduled" fallback (they had diverged: schedule-nothing vs.
    /// a 1-hour timer). The `now + 1h` at the end is an unreachable last resort for the (impossible)
    /// case where even `Calendar.date(byAdding: .day, value: 1, ...)` fails.
    ///
    /// Two things move the Stage independently of user action:
    /// 1. **Slot edges** — a window opening/closing changes Current/Upcoming. → `nextTransitionTime`.
    /// 2. **Cycle rollover** — at a cycle boundary a goal-met commitment becomes un-met and reappears,
    ///    check-in counts reset, `behindCount` shifts. This has no slot edge at that instant, so it
    ///    must be woken for separately.
    ///
    /// The *conceptually correct* second term is "the closest cycle end across all commitments". We
    /// approximate it with **the next psychDay (start-of-day) boundary**: every cycle boundary lands on
    /// a start-of-day (see `Cycle.startDayOfCycle`, which normalizes daily/weekly/monthly to
    /// `startOfDay`), so the next midnight is always on-or-before the next real cycle end. Waking at
    /// every midnight fires at most one harmless extra time per day (a no-op recompute) and needs no
    /// per-commitment cycle math — a deliberate simplicity-over-precision trade. If that extra daily
    /// wake ever matters, replace the psychDay term with the true `min` over commitments' cycle ends.
    static func nextStageRefreshTime(
        commitments: [Commitment], now: Date = Time.now()
    ) -> Date {
        let nextPsychDayBoundary = Time.calendar.date(
            byAdding: .day, value: 1, to: Time.startOfDay(for: now))
        return [
            nextTransitionTime(commitments: commitments, now: now),
            nextPsychDayBoundary,
        ].compactMap(\.self).min()
            ?? now.addingTimeInterval(60 * 60)  // calendar +1day can't fail; last-resort only
    }

}
