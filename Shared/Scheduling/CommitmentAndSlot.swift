import Foundation

enum CommitmentAndSlot {
    /// Shared tuple used by Stage to render rows with behind information.
    typealias WithBehind = (commitment: Commitment, slots: [SlotOccurrence], behindCount: Int)

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

    /// Commitments that should fire a catch-up reminder: behind, and **not** currently in an open slot
    /// (a commitment being acted on right now doesn't also need a nudge). Reads the characterization
    /// layer directly, so it includes behind commitments regardless of which Stage bucket they land in
    /// (e.g. a behind one sitting in Upcoming's top-N is still reminded).
    static func behindForReminder(
        characteristics: [CommitmentCharacteristics]
    ) -> [CommitmentCharacteristics] {
        characteristics.filter { $0.isBehind && !$0.isCurrent }
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

    static func currentWithBehind(
        commitments: [Commitment],
        now: Date = Time.now()
    ) -> [WithBehind] {
        let result: [WithBehind] = commitments.compactMap { commitment in
            guard commitment.isActiveForReminders(now: now) else { return nil }  // safe net
            let status = commitment.status(now: now)
            guard status.slotKind == .insideSlot else { return nil }
            return (
                commitment: commitment, slots: status.remainingSlots ?? [],
                behindCount: status.behindCount ?? 0
            )
        }
        // Sort by remaining fraction of the current slot window (sooner-to-end first).
        return result.sorted {
            $0.slots[0].remainingFraction(at: now) < $1.slots[0].remainingFraction(at: now)
        }
    }

    static func upcomingWithBehind(
        commitments: [Commitment],
        after time: Date
    ) -> [WithBehind] {
        let result: [WithBehind] = commitments.compactMap { commitment in
            guard commitment.isActiveForReminders(now: time) else { return nil }
            let status = commitment.status(now: time)
            guard status.slotKind == .beforeNextToday else { return nil }
            return (
                commitment: commitment, slots: status.remainingSlots ?? [],
                behindCount: status.behindCount ?? 0
            )
        }
        // Sort by first upcoming slot start, then end.
        return result.sorted {
            guard let lhs = $0.slots.first, let rhs = $1.slots.first else { return false }
            if lhs.start == rhs.start { return lhs.end < rhs.end }
            return lhs.start < rhs.start
        }
    }

    static func catchUpWithBehind(
        commitments: [Commitment],
        now: Date = Time.now()
    ) -> [WithBehind] {
        let result: [WithBehind] = commitments.compactMap { commitment in
            guard commitment.isActiveForReminders(now: now) else { return nil }
            let status = commitment.status(now: now)
            guard status.slotKind == .noSlotToday else { return nil }
            guard let behindCount = status.behindCount, behindCount > 0 else { return nil }
            return (
                commitment: commitment, slots: status.remainingSlots ?? [], behindCount: behindCount
            )
        }
        // Self-contained legacy sort (same urgency order). This helper + its sort are deleted in 6g;
        // keeping the closure inline avoids coupling it to the new characteristics-based ordering.
        return result.sorted { lhs, rhs in
            let lhsTargetCount = max(lhs.commitment.target.count, 1)
            let rhsTargetCount = max(rhs.commitment.target.count, 1)
            let lhsUrgency = Double(lhs.behindCount) / Double(lhsTargetCount)
            let rhsUrgency = Double(rhs.behindCount) / Double(rhsTargetCount)
            if lhsUrgency != rhsUrgency { return lhsUrgency > rhsUrgency }
            if lhs.commitment.target.count != rhs.commitment.target.count {
                return lhs.commitment.target.count > rhs.commitment.target.count
            }
            guard let lhsSlot = lhs.slots.first, let rhsSlot = rhs.slots.first else {
                if lhs.slots.isEmpty, !rhs.slots.isEmpty { return false }
                if !lhs.slots.isEmpty, rhs.slots.isEmpty { return true }
                return false
            }
            if lhsSlot.start == rhsSlot.start { return lhsSlot.end < rhsSlot.end }
            return lhsSlot.start < rhsSlot.start
        }
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
