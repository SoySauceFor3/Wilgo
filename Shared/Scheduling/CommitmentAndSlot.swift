import Foundation

enum CommitmentAndSlot {
    /// Shared tuple used by Stage to render rows with behind information.
    typealias WithBehind = (commitment: Commitment, slots: [Slot], behindCount: Int)

    static func currentWithBehind(
        commitments: [Commitment],
        now: Date = Time.now()
    ) -> [WithBehind] {
        let result: [WithBehind] = commitments.compactMap { commitment in
            guard commitment.isActiveForReminders(now: now) else { return nil }
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
        // Sort primarily by behindCount/targetCount (higher is more urgent),
        // then by larger target count,
        // then by earliest next slot (if any).
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
