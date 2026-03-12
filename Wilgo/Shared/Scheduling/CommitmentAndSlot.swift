import Foundation

enum CommitmentAndSlot {
    static func current(
        commitments: [Commitment],
        now: Date = CommitmentScheduling.now()
    ) -> [(Commitment, [Slot])] {
        let currentCommitmentAndSlots = commitments.compactMap {
            commitment -> (Commitment, [Slot])? in
            let stageStatus = commitment.stageStatus(now: now)
            if stageStatus.category == .current {
                return (commitment, stageStatus.nextUpSlots)
            }
            return nil
        }

        // sort currentCommitmentAndSlots by currentCommitmentAndSlots.nextUpSlots[0]'s fraction of remaining time
        return currentCommitmentAndSlots.sorted {
            $0.1[0].remainingFraction(at: now) < $1.1[0].remainingFraction(at: now)
        }
    }

    // For each commitment that has NOT yet met today (psychological day)'s goal,
    // return the first slot that hasn't started yet.
    static func upcoming(
        commitments: [Commitment],
        after time: Date
    ) -> [(Commitment, [Slot])] {
        let upcomingCommitmentAndSlots = commitments.compactMap {
            commitment -> (Commitment, [Slot])? in
            let stageStatus = commitment.stageStatus(now: time)
            if stageStatus.category == .future {
                return (commitment, stageStatus.nextUpSlots)
            }
            return nil
        }

        // sort upcomingCommitmentAndSlots by upcomingCommitmentAndSlots.nextUpSlots[0]
        return upcomingCommitmentAndSlots.sorted {
            if $0.1[0].start == $1.1[0].start {
                return $0.1[0].end < $1.1[0].end
            } else {
                return $0.1[0].start < $1.1[0].start
            }
        }
    }

    static func catchUp(
        commitments: [Commitment],
        now: Date = CommitmentScheduling.now()
    ) -> [(Commitment, [Slot])] {
        let catchUpCommitmentAndSlots = commitments.compactMap {
            commitment -> (Commitment, [Slot])? in
            let stageStatus = commitment.stageStatus(now: now)
            if stageStatus.category == .catchUp {
                return (commitment, stageStatus.nextUpSlots)
            }
            return nil
        }

        return catchUpCommitmentAndSlots.sorted {
            // TODO: THIS NEED TO CHANGED!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! It only supports daily cycle for target.
            // Calculate the fraction of "late progress"/"total target" and use it to sort, higher fraction in front.
            // If fractions are equal to 1, then commitment with larger goalCountPerDay comes first.

            func catchUpFraction(_ tuple: (Commitment, [Slot])) -> Double {
                let (commitment, nextUpSlots) = tuple
                let catchUpCount = max(
                    commitment.target.countPerCycle
                        - commitment.completedCount(for: CommitmentScheduling.psychDay(for: now))
                        - nextUpSlots.count, 0)
                guard commitment.target.countPerCycle > 0 else { return 0 }
                return Double(catchUpCount) / Double(commitment.target.countPerCycle)
            }

            let lhsFraction = catchUpFraction($0)
            let rhsFraction = catchUpFraction($1)

            if lhsFraction == rhsFraction {
                if lhsFraction == 1.0 {
                    // Larger goalCountPerDay first if both at max fraction.
                    return $0.0.target.countPerCycle > $1.0.target.countPerCycle
                } else {
                    // Tiebreaker: start of first slot
                    return $0.1[0].start < $1.1[0].start
                }
            } else {
                // Higher fraction comes first
                return lhsFraction > rhsFraction
            }
        }
    }

    /// Earliest upcoming windowStart, windowEnd, or psychDay boundary across all commitments' slots.
    static func nextTransitionDate(
        commitments: [Commitment], now: Date = CommitmentScheduling.now()
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
        let currentPsychDayBase = CommitmentScheduling.psychDay(for: now)
        if let nextPsychDayBase = CommitmentScheduling.calendar.date(
            byAdding: .day, value: 1, to: currentPsychDayBase)
        {
            let nextPsychDayStart = nextPsychDayBase.addingTimeInterval(
                TimeInterval(CommitmentScheduling.dayStartHourOffset * 3_600))
            if nextPsychDayStart > now { candidates.append(nextPsychDayStart) }
        }

        return candidates.min()
    }
}
