import Foundation

/// Builds a `CycleRecord` snapshot from a cycle's report + the user's card state
/// at the moment the FCR is closed.
///
/// Snapshots the title and counts so later edits (renames, backfills, deletions)
/// don't rewrite history. Passed cycles carry emoji reactions and no outcome;
/// failed cycles carry the outcome label, reflection, and consumed PT.
enum CycleRecordBuilder {
    static func makeRecord(
        commitment: Commitment,
        cycle: CycleReport,
        state: FCRCycleCardState,
        consumedPT: PositivityToken?,
        recordedAt: Date = .now
    ) -> CycleRecord {
        if state.isPassed {
            return CycleRecord(
                commitment: commitment,
                snapshotTitle: commitment.title,
                cycleStart: cycle.cycleStartPsychDay,
                cycleEnd: cycle.cycleEndPsychDay,
                targetCount: state.targetCount,
                checkInCount: state.checkInCount,
                outcome: .passed,
                reflectionText: nil,
                emojiReactions: state.emojiReactions,
                consumedPT: nil,
                recordedAt: recordedAt
            )
        } else {
            // Only outcomes that require a PT (Move on, Punished) consume one.
            // Intended/Excused must never consume a PT even if one is passed in.
            let pt = (state.outcome?.requiresPT == true) ? consumedPT : nil
            return CycleRecord(
                commitment: commitment,
                snapshotTitle: commitment.title,
                cycleStart: cycle.cycleStartPsychDay,
                cycleEnd: cycle.cycleEndPsychDay,
                targetCount: state.targetCount,
                checkInCount: state.checkInCount,
                outcome: state.outcome,
                reflectionText: state.reflectionText,
                emojiReactions: [],
                consumedPT: pt,
                recordedAt: recordedAt
            )
        }
    }
}
