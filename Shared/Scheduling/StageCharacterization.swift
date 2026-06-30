import Foundation

enum CommitmentAndSlot {
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

    /// Earliest upcoming windowStart, windowEnd, or psychDay boundary across all commitments' slots.
    ///
    /// Intentionally does NOT apply `isActiveForReminders`: a goal-met commitment can become
    /// un-met across a cycle boundary, and waking slightly early is harmless — whereas filtering
    /// here could skip a needed wake-up. This is the one helper that does not gate on that rule.
    static func nextTransitionDate(
        commitments: [Commitment], now: Date = Time.now()
    ) -> Date? {
        var candidates: [Date] = []
        for commitment in commitments {
            for slot in commitment.slots {
                let start = slot.startToday
                let end = slot.endToday
                if start > now { candidates.append(start) }
                if end > now { candidates.append(end) }
            }
        }
        // Wake up exactly at the next psychDay boundary so the Stage resets on time
        // even when no slot transitions remain in the current day.
        let currentPsychDayBase = Time.startOfDay(for: now)
        if let nextPsychDayBase = Time.calendar.date(
            byAdding: .day, value: 1, to: currentPsychDayBase)
        {
            if nextPsychDayBase > now { candidates.append(nextPsychDayBase) }
        }
        return candidates.min()
    }

}
