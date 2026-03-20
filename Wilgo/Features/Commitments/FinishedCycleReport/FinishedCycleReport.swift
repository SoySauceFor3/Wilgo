import Foundation
import SwiftData

struct FinishedCycleReport: Identifiable {
    struct CommitmentReport: Identifiable {
        let id: String
        let commitmentTitle: String
        let cycles: [CycleReport]
    }

    struct CycleReport: Identifiable {
        let id: String
        let actualCheckIns: Int
        let targetCheckIns: Int
        let cycleLabel: String
        let aidedByPositivityTokenCount: Int

        var compensatedCheckIns: Int { actualCheckIns + aidedByPositivityTokenCount }
        var metTarget: Bool { compensatedCheckIns >= targetCheckIns }
        var isAidedByPositivityToken: Bool { aidedByPositivityTokenCount > 0 }
    }

    let id = UUID()
    let commitments: [CommitmentReport]
}

enum FinishedCycleReportBuilder {
    private static var calendar: Calendar { Time.calendar }
    private static let monthlyCapDefault = 5

    private struct CycleDraft {
        let commitmentID: String
        let commitmentTitle: String
        let cycleID: String
        let cycleLabel: String
        let cycleEndPsychDay: Date
        let actualCheckIns: Int
        let targetCheckIns: Int
    }

    static func build(
        commitments: [Commitment],
        startPsychDay: Date,  // inclusive
        endPsychDay: Date,  // exclusive
        allTokens: [PositivityToken],
        monthlyCap: Int? = nil
    ) -> FinishedCycleReport {
        guard startPsychDay < endPsychDay else {
            return FinishedCycleReport(commitments: [])
        }

        let cycleDrafts =
            commitments
            .flatMap { cyclesForCommitment(for: $0, from: startPsychDay, to: endPsychDay) }
        guard !cycleDrafts.isEmpty else {
            return FinishedCycleReport(commitments: [])
        }

        let cap = monthlyCap ?? positivityTokenMonthlyCap()
        let cycleNeeds = cycleDrafts.map { draft in
            PositivityCycleNeed(
                cycleID: draft.cycleID,
                commitmentID: draft.commitmentID,
                cycleEndPsychDay: draft.cycleEndPsychDay,
                missingCheckIns: max(0, draft.targetCheckIns - draft.actualCheckIns)
            )
        }
        let aidedTokenCountByCycleID = PositivityTokenCompensator.apply(
            cycleNeeds: cycleNeeds,
            tokens: allTokens,
            monthlyCap: cap,
            calendar: calendar
        )

        let commitmentReports: [FinishedCycleReport.CommitmentReport] = Dictionary(
            grouping: cycleDrafts, by: \.commitmentID
        )
        .compactMap { commitmentID, drafts -> FinishedCycleReport.CommitmentReport? in
            guard let first = drafts.first else { return nil }
            let sortedDrafts = drafts.sorted { $0.cycleEndPsychDay < $1.cycleEndPsychDay }
            return FinishedCycleReport.CommitmentReport(
                id: commitmentID,
                commitmentTitle: first.commitmentTitle,
                cycles: sortedDrafts.map { draft in
                    FinishedCycleReport.CycleReport(
                        id: draft.cycleID,
                        actualCheckIns: draft.actualCheckIns,
                        targetCheckIns: draft.targetCheckIns,
                        cycleLabel: draft.cycleLabel,
                        aidedByPositivityTokenCount: aidedTokenCountByCycleID[
                            draft.cycleID, default: 0]
                    )
                }
            )
        }
        .sorted { $0.commitmentTitle < $1.commitmentTitle }

        return FinishedCycleReport(commitments: commitmentReports)
    }

    private static func cyclesForCommitment(
        for commitment: Commitment,
        from startPsychDay: Date,  // inclusive
        to endPsychDay: Date  // exclusive
    ) -> [CycleDraft] {
        let cycle = commitment.target.cycle
        var cycleCursorDay = startPsychDay
        var cycles: [CycleDraft] = []

        while let cycleEnd = nextCompletedCycleEnd(
            for: cycle,
            cursor: cycleCursorDay,
            now: endPsychDay
        ) {
            let cycleLabelDay = previousPsychDay(cycleEnd)
            let cycleStart = cycle.startDayOfCycle(including: cycleLabelDay)
            let actualCheckIns = commitment.checkInsInRange(
                startPsychDay: cycleStart,
                endPsychDay: cycleEnd
            ).count

            let cycleID = reportItemID(for: commitment, cycleEndPsychDay: cycleEnd)
            cycles.append(
                CycleDraft(
                    commitmentID: commitment.persistentModelID.encoded(),
                    commitmentTitle: commitment.title,
                    cycleID: cycleID,
                    cycleLabel: cycle.label(of: cycleLabelDay),
                    cycleEndPsychDay: cycleEnd,
                    actualCheckIns: actualCheckIns,
                    targetCheckIns: commitment.target.count,
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
        calendar.date(byAdding: .day, value: -1, to: date) ?? date
    }

    private static func reportItemID(for commitment: Commitment, cycleEndPsychDay: Date) -> String {
        "\(commitment.persistentModelID.encoded())::\(cycleEndPsychDay.timeIntervalSinceReferenceDate)"
    }

    private static func toPsychDayRef(_ date: Date) -> Double {
        date.timeIntervalSinceReferenceDate
    }

    private static func fromPsychDayRef(_ ref: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: ref)
    }

    private static func positivityTokenMonthlyCap() -> Int {
        let value: Int
        if UserDefaults.standard.object(forKey: AppSettings.positivityTokenMonthlyCapKey) == nil {
            value = monthlyCapDefault
        } else {
            value = UserDefaults.standard.integer(forKey: AppSettings.positivityTokenMonthlyCapKey)
        }
        return max(0, value)
    }

    /// Full entry-point for UI callers.
    /// Reads persisted watermark, computes report decision, persists updated
    /// watermark, and returns the report to present (if any).
    ///
    /// Notes:
    /// - If persisted watermark is `0`, this is first app run: establish baseline
    ///   at current psych-day and do not show historical cycles.
    /// - Empty reports still advance watermark, but return `nil`.
    static func consumePendingReport(
        commitments: [Commitment],
        allTokens: [PositivityToken]
    ) -> FinishedCycleReport? {
        let previousRef = UserDefaults.standard.double(
            forKey: AppSettings.finishedCycleReportLastShownPsychDayKey
        )
        let nowPsychDay = Time.psychDay(for: Time.now())
        let nowPsychDayRef = toPsychDayRef(nowPsychDay)
        // Persist watermark updates regardless of whether we show anything.
        UserDefaults.standard.set(
            nowPsychDayRef,
            forKey: AppSettings.finishedCycleReportLastShownPsychDayKey
        )
        // First bootstrap: establish baseline and do not show historical cycles.
        guard previousRef != 0 else {
            return nil
        }

        let report = build(
            commitments: commitments,
            startPsychDay: fromPsychDayRef(previousRef),
            endPsychDay: nowPsychDay,
            allTokens: allTokens
        )

        return report.commitments.isEmpty ? nil : report
    }
}
