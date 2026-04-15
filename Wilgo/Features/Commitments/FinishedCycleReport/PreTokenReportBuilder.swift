import Foundation
import SwiftData

enum PreTokenReportBuilder {
    private struct CycleDraft {
        let commitmentID: UUID
        let commitmentTitle: String
        let cycleID: String
        let cycleLabel: String
        let cycleStartPsychDay: Date
        let cycleEndPsychDay: Date
        let checkIns: [CheckIn]
        let targetCheckIns: Int
        let isGrace: Bool

        var actualCheckIns: Int { checkIns.count }
    }

    /// Phase 1: builds raw cycles from committed check-in data, with no positivity
    /// token compensation applied (`consumedPTReasons` is `[]` for every cycle).
    /// Feed the result into `applyPositivityTokens` for the final PT-compensated report.
    static func build(
        commitments: [Commitment],
        startPsychDay: Date,  // inclusive
        endPsychDay: Date  // exclusive
    ) -> [CommitmentReport] {
        guard startPsychDay < endPsychDay else {
            return []
        }
        let cycleDrafts =
            commitments
            .flatMap { cyclesForCommitment(for: $0, from: startPsychDay, to: endPsychDay) }
        guard !cycleDrafts.isEmpty else {
            return []
        }
        let commitmentByID = Dictionary(
            uniqueKeysWithValues: commitments.map { ($0.id, $0) }
        )
        let commitmentReports: [CommitmentReport] = Dictionary(
            grouping: cycleDrafts, by: \.commitmentID
        )
        .compactMap { commitmentID, drafts -> CommitmentReport? in
            guard let commitment = commitmentByID[commitmentID] else { return nil }
            let sortedDrafts = drafts.sorted { $0.cycleEndPsychDay < $1.cycleEndPsychDay }
            return CommitmentReport(
                id: commitmentID,
                commitment: commitment,
                cycles: sortedDrafts.map { draft in
                    CycleReport(
                        id: draft.cycleID,
                        actualCheckIns: draft.actualCheckIns,
                        targetCheckIns: draft.targetCheckIns,
                        cycleLabel: draft.cycleLabel,
                        cycleStartPsychDay: draft.cycleStartPsychDay,
                        cycleEndPsychDay: draft.cycleEndPsychDay,
                        consumedPTReasons: [],
                        checkIns: draft.checkIns,
                        isGrace: draft.isGrace
                    )
                }
            )
        }
        .sorted { $0.commitment.title < $1.commitment.title }
        return commitmentReports
    }

    private static func cyclesForCommitment(
        for commitment: Commitment,
        from startPsychDay: Date,  // inclusive
        to endPsychDay: Date  // exclusive
    ) -> [CycleDraft] {
        let cycle = commitment.cycle
        let commitmentID = commitment.id
        var cycleCursorDay = startPsychDay
        var cycles: [CycleDraft] = []

        while let cycleEnd = nextCompletedCycleEnd(
            for: cycle,
            cursor: cycleCursorDay,
            now: endPsychDay
        ) {
            let cycleLabelDay = previousPsychDay(cycleEnd)
            let cycleStart = cycle.startDayOfCycle(including: cycleLabelDay)
            let cycleCheckIns = commitment.checkInsInRange(
                startPsychDay: cycleStart,
                endPsychDay: cycleEnd
            )

            let isGrace = commitment.gracePeriods.contains {
                $0.overlaps(cycleStart: cycleStart, cycleEnd: cycleEnd)
            }
            let cycleID = "\(commitmentID)::\(cycleEnd.timeIntervalSinceReferenceDate)"
            cycles.append(
                CycleDraft(
                    commitmentID: commitmentID,
                    commitmentTitle: commitment.title,
                    cycleID: cycleID,
                    cycleLabel: cycle.label(of: cycleLabelDay),
                    cycleStartPsychDay: cycleStart,
                    cycleEndPsychDay: cycleEnd,
                    checkIns: cycleCheckIns,
                    targetCheckIns: commitment.target.count,
                    isGrace: isGrace
                )
            )
            cycleCursorDay = cycleEnd
        }
        return cycles
    }

    private static func nextCompletedCycleEnd(
        for cycle: Cycle,
        cursor: Date,
        now: Date
    ) -> Date? {
        let cycleEnd = cycle.endDayOfCycle(including: cursor)
        return cycleEnd <= now ? cycleEnd : nil
    }

    private static func previousPsychDay(_ date: Date) -> Date {
        Time.calendar.date(byAdding: .day, value: -1, to: date) ?? date
    }

}
