import Foundation

enum CommitmentAndSlot {
    /// Shared tuple used by Stage to render rows with behind information.
    typealias WithBehind = (commitment: Commitment, slots: [Slot], behindCount: Int)

    static func currentWithBehind(
        commitments: [Commitment],
        now: Date = Time.now()
    ) -> [WithBehind] {
        let currentCommitmentAndSlots: [WithBehind] = commitments.compactMap { commitment in
            let stageStatus = commitment.stageStatus(now: now)
            guard stageStatus.category == .current else { return nil }
            return (
                commitment: commitment,
                slots: stageStatus.nextUpSlots,
                behindCount: stageStatus.behindCount
            )
        }

        // Sort by remaining fraction of the current slot window (sooner-to-end first).
        return currentCommitmentAndSlots.sorted {
            $0.slots[0].remainingFraction(at: now) < $1.slots[0].remainingFraction(at: now)
        }
    }

    static func upcomingWithBehind(
        commitments: [Commitment],
        after time: Date
    ) -> [WithBehind] {
        let upcomingCommitmentAndSlots: [WithBehind] = commitments.compactMap { commitment in
            let stageStatus = commitment.stageStatus(now: time)
            guard stageStatus.category == .future else { return nil }
            return (
                commitment: commitment,
                slots: stageStatus.nextUpSlots,
                behindCount: stageStatus.behindCount
            )
        }

        // Sort by first upcoming slot start, then end.
        return upcomingCommitmentAndSlots.sorted {
            guard let lhs = $0.slots.first, let rhs = $1.slots.first else { return false }
            if lhs.start == rhs.start {
                return lhs.end < rhs.end
            } else {
                return lhs.start < rhs.start
            }
        }
    }

    static func catchUpWithBehind(
        commitments: [Commitment],
        now: Date = Time.now()
    ) -> [WithBehind] {
        let catchUpCommitmentAndSlots: [WithBehind] = commitments.compactMap { commitment in
            let stageStatus = commitment.stageStatus(now: now)
            guard stageStatus.category == .catchUp else { return nil }
            return (
                commitment: commitment,
                slots: stageStatus.nextUpSlots,
                behindCount: stageStatus.behindCount
            )
        }

        // Sort primarily by behindCount/targetCount (higher is better),
        // then by larger target count,
        // then by earliest next slot (if any).
        return catchUpCommitmentAndSlots.sorted { lhs, rhs in
            // Compute "urgency" as the ratio, larger is more urgent
            let lhsTargetCount = max(lhs.commitment.target.count, 1)
            let rhsTargetCount = max(rhs.commitment.target.count, 1)
            let lhsUrgency = Double(lhs.behindCount) / Double(lhsTargetCount)
            let rhsUrgency = Double(rhs.behindCount) / Double(rhsTargetCount)

            if lhsUrgency != rhsUrgency {
                return lhsUrgency > rhsUrgency
            }

            if lhs.commitment.target.count != rhs.commitment.target.count {
                return lhs.commitment.target.count > rhs.commitment.target.count
            }

            guard let lhsSlot = lhs.slots.first, let rhsSlot = rhs.slots.first else {
                if lhs.slots.isEmpty && !rhs.slots.isEmpty { return false }
                if !lhs.slots.isEmpty && rhs.slots.isEmpty { return true }
                return false
            }

            if lhsSlot.start == rhsSlot.start {
                return lhsSlot.end < rhsSlot.end
            } else {
                return lhsSlot.start < rhsSlot.start
            }
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
            let nextPsychDayStart = nextPsychDayBase
            if nextPsychDayStart > now { candidates.append(nextPsychDayStart) }
        }
        return candidates.min()
    }
}
