import Foundation

enum CommitmentAndSlot {
    /// Shared tuple used by Stage to render rows with behind information.
    typealias WithBehind = (commitment: Commitment, slots: [SlotOccurrence], behindCount: Int)

    /// One Upcoming row. Carries the single nearest usable slot plus what the row needs to render
    /// its "current-cycle +k more" vs "future cycle" variants (PRD §9).
    struct UpcomingEntry: Equatable {
        let commitment: Commitment
        /// The commitment's nearest usable upcoming slot occurrence (the row's headline time).
        let nearestSlot: SlotOccurrence
        /// True when `nearestSlot` falls in the cycle that contains `now`. When false the row is a
        /// future-cycle row (exact datetime + "future cycle" marker, no "+k more").
        let isInCurrentCycle: Bool
        /// Usable slot occurrences remaining in the *current* cycle (drives "+k more": `count - 1`).
        /// Only meaningful when `isInCurrentCycle` is true.
        let currentCycleRemainingCount: Int
        let behindCount: Int
    }

    /// How an Upcoming row should render its time line (PRD §9). Pure value so the decision is
    /// unit-tested without a view.
    enum UpcomingRowDisplay: Equatable {
        /// Nearest slot is in the current cycle: show the time-of-day, plus "+k more" when
        /// `extraCount > 0` (other usable slots remaining in this cycle).
        case currentCycle(timeText: String, extraCount: Int)
        /// Nearest slot is in a future cycle: show its exact datetime + a "future cycle" marker.
        case futureCycle(dateTimeText: String)
    }

    /// The combined Stage buckets for `now`, with the closest-N Upcoming rule and the
    /// Upcoming-takes-priority / overflow-demotes-to-Catch-up rule wired in one place.
    ///
    /// - **Current**: active commitments with an open slot right now (`.insideSlot`).
    /// - **Upcoming**: the `n` active, non-current commitments whose nearest usable upcoming slot is
    ///   soonest (ranked across commitments, then capped at `n`).
    /// - **Catch-up**: active, behind commitments that are *not* in Upcoming — i.e. those with no
    ///   usable upcoming slot at all, plus those whose nearest slot exists but fell outside the
    ///   top-`n` (overflow demotion).
    ///
    /// A commitment appears in exactly one bucket. `n` counts commitments, not slots.
    static func stageBuckets(
        commitments: [Commitment],
        now: Date = Time.now(),
        n: Int
    ) -> (current: [WithBehind], upcoming: [UpcomingEntry], catchUp: [WithBehind]) {
        let active = commitments.filter { $0.isActiveForReminders(now: now) }

        let current = currentWithBehind(commitments: active, now: now)
        let currentIDs = Set(current.map(\.commitment.id))

        // Future-eligible: active, not already Current, with a nearest usable upcoming slot.
        // Build entries carrying that slot so we can rank by it and render the row.
        let futureEligible: [UpcomingEntry] =
            active
            .filter { !currentIDs.contains($0.id) }
            .compactMap { commitment in
                guard let nearest = commitment.nearestUsableUpcomingOccurrence(now: now) else {
                    return nil
                }
                let status = commitment.status(now: now)
                let cycleBounds = commitment.cycle.bounds(including: now)
                let inCurrentCycle =
                    nearest.start >= cycleBounds.start && nearest.start < cycleBounds.end
                return UpcomingEntry(
                    commitment: commitment,
                    nearestSlot: nearest,
                    isInCurrentCycle: inCurrentCycle,
                    currentCycleRemainingCount: status.remainingSlots?.count ?? 0,
                    behindCount: status.behindCount ?? 0
                )
            }
            .sorted {
                if $0.nearestSlot.start == $1.nearestSlot.start {
                    return $0.nearestSlot.end < $1.nearestSlot.end
                }
                return $0.nearestSlot.start < $1.nearestSlot.start
            }

        let upcoming = Array(futureEligible.prefix(max(0, n)))
        let upcomingIDs = Set(upcoming.map(\.commitment.id))

        // Catch-up: active, behind, and not in Upcoming. Covers both "no upcoming slot at all" and
        // overflow (had a slot but ranked beyond the top-n).
        let catchUp = catchUpDemoted(
            active: active,
            excluding: currentIDs.union(upcomingIDs),
            now: now
        )

        return (current: current, upcoming: upcoming, catchUp: catchUp)
    }

    /// Active, behind commitments not already shown in Current or Upcoming, sorted by the shared
    /// catch-up urgency ordering.
    private static func catchUpDemoted(
        active: [Commitment],
        excluding excludedIDs: Set<UUID>,
        now: Date
    ) -> [WithBehind] {
        let result: [WithBehind] = active.compactMap { commitment in
            guard !excludedIDs.contains(commitment.id) else { return nil }
            let status = commitment.status(now: now)
            guard let behindCount = status.behindCount, behindCount > 0 else { return nil }
            return (
                commitment: commitment, slots: status.remainingSlots ?? [], behindCount: behindCount
            )
        }
        return result.sorted(by: Self.catchUpUrgencyOrder)
    }

    /// Catch-up urgency ordering: by `behindCount / targetCount` (higher first), then larger target
    /// count, then earliest next slot. A stored closure (not a method) so it stays nonisolated and
    /// is usable from both `@MainActor` and non-isolated callers (e.g. the widget timeline).
    private static let catchUpUrgencyOrder: (WithBehind, WithBehind) -> Bool = { lhs, rhs in
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
        return result.sorted(by: Self.catchUpUrgencyOrder)
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

extension CommitmentAndSlot.UpcomingEntry {
    /// The row's time-line rendering decision (PRD §9): current-cycle time + optional "+k more",
    /// or a future-cycle exact datetime. View-agnostic so it can be tested directly.
    var rowDisplay: CommitmentAndSlot.UpcomingRowDisplay {
        if isInCurrentCycle {
            return .currentCycle(
                timeText: nearestSlot.timeOfDayText,
                extraCount: max(0, currentCycleRemainingCount - 1)
            )
        } else {
            // Future-cycle row: anchor date + full window, via SlotOccurrence's own formatting.
            return .futureCycle(dateTimeText: nearestSlot.datedLabel)
        }
    }
}
