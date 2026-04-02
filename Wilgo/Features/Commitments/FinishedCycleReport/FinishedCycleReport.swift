import Foundation
import SwiftData

struct FinishedCycleReport: Identifiable {
    struct CommitmentReport: Identifiable {
        let id: String
        let commitment: Commitment
        let cycles: [CycleReport]

        var commitmentTitle: String { commitment.title }
    }

    struct CycleReport: Identifiable {
        let id: String
        let actualCheckIns: Int
        let targetCheckIns: Int
        let cycleLabel: String
        let cycleStartPsychDay: Date  // inclusive
        let cycleEndPsychDay: Date  // exclusive
        let aidedByPositivityTokenCount: Int
        let checkIns: [CheckIn]

        var compensatedCheckIns: Int { actualCheckIns + aidedByPositivityTokenCount }
        var metTarget: Bool { compensatedCheckIns >= targetCheckIns }
        var isAidedByPositivityToken: Bool { aidedByPositivityTokenCount > 0 }
    }

    let id = UUID()
    let commitments: [CommitmentReport]
}

/// A lightweight token passed to `FinishedCycleReportSheet` that captures the
/// date window for the report.  The sheet re-derives the full report live from
/// `@Query` sources, so backfills and other data changes are reflected
/// automatically without any parent involvement.
struct FinishedCycleReportRequest: Identifiable {
    let id = UUID()
    let startPsychDay: Date  // inclusive
    let endPsychDay: Date  // exclusive
}

enum FinishedCycleReportBuilder {
    private static var calendar: Calendar { Time.calendar }
    private static let monthlyCapDefault = 5

    private struct CycleDraft {
        let commitmentID: PersistentIdentifier
        let commitmentTitle: String
        let cycleID: String
        let cycleLabel: String
        let cycleStartPsychDay: Date
        let cycleEndPsychDay: Date
        let checkIns: [CheckIn]
        let targetCheckIns: Int

        var actualCheckIns: Int { checkIns.count }
    }

    /// Phase 1: builds raw cycles from committed check-in data, with no positivity
    /// token compensation applied (`aidedByPositivityTokenCount` is 0 for every cycle).
    /// Feed the result into `applyPositivityTokens` for the final PT-compensated report.
    static func buildPreToken(
        commitments: [Commitment],
        startPsychDay: Date,  // inclusive
        endPsychDay: Date  // exclusive
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
        let commitmentByID = Dictionary(
            uniqueKeysWithValues: commitments.map { ($0.persistentModelID, $0) }
        )
        let commitmentReports: [FinishedCycleReport.CommitmentReport] = Dictionary(
            grouping: cycleDrafts, by: \.commitmentID
        )
        .compactMap { commitmentID, drafts -> FinishedCycleReport.CommitmentReport? in
            guard let commitment = commitmentByID[commitmentID] else { return nil }
            let sortedDrafts = drafts.sorted { $0.cycleEndPsychDay < $1.cycleEndPsychDay }
            return FinishedCycleReport.CommitmentReport(
                id: commitmentID.encoded(),
                commitment: commitment,
                cycles: sortedDrafts.map { draft in
                    FinishedCycleReport.CycleReport(
                        id: draft.cycleID,
                        actualCheckIns: draft.actualCheckIns,
                        targetCheckIns: draft.targetCheckIns,
                        cycleLabel: draft.cycleLabel,
                        cycleStartPsychDay: draft.cycleStartPsychDay,
                        cycleEndPsychDay: draft.cycleEndPsychDay,
                        aidedByPositivityTokenCount: 0,
                        checkIns: draft.checkIns
                    )
                }
            )
        }
        .sorted { $0.commitmentTitle < $1.commitmentTitle }
        return FinishedCycleReport(commitments: commitmentReports)
    }

    /// Phase 2: takes a pre-token report and returns a new report with positivity
    /// token compensation applied to each cycle's `aidedByPositivityTokenCount`.
    static func applyPositivityTokens(
        to report: FinishedCycleReport,
        allTokens: [PositivityToken],
        monthlyCap: Int? = nil
    ) -> FinishedCycleReport {
        guard !report.commitments.isEmpty else { return report }
        let cap = monthlyCap ?? positivityTokenMonthlyCap()
        let cycleNeeds = report.commitments.flatMap { commitmentReport in
            commitmentReport.cycles.map { cycle in
                PositivityCycleNeed(
                    cycleID: cycle.id,
                    commitmentID: commitmentReport.commitment.persistentModelID,
                    cycleEndPsychDay: cycle.cycleEndPsychDay,
                    missingCheckIns: max(0, cycle.targetCheckIns - cycle.actualCheckIns)
                )
            }
        }
        let aidedTokenCountByCycleID = PositivityTokenCompensator.apply(
            cycleNeeds: cycleNeeds,
            tokens: allTokens,
            monthlyCap: cap,
            calendar: calendar
        )
        let updatedCommitments = report.commitments.map { commitmentReport in
            FinishedCycleReport.CommitmentReport(
                id: commitmentReport.id,
                commitment: commitmentReport.commitment,
                cycles: commitmentReport.cycles.map { cycle in
                    FinishedCycleReport.CycleReport(
                        id: cycle.id,
                        actualCheckIns: cycle.actualCheckIns,
                        targetCheckIns: cycle.targetCheckIns,
                        cycleLabel: cycle.cycleLabel,
                        cycleStartPsychDay: cycle.cycleStartPsychDay,
                        cycleEndPsychDay: cycle.cycleEndPsychDay,
                        aidedByPositivityTokenCount: aidedTokenCountByCycleID[cycle.id, default: 0],
                        checkIns: cycle.checkIns
                    )
                }
            )
        }
        return FinishedCycleReport(commitments: updatedCommitments)
    }

    private static func cyclesForCommitment(
        for commitment: Commitment,
        from startPsychDay: Date,  // inclusive
        to endPsychDay: Date  // exclusive
    ) -> [CycleDraft] {
        let cycle = commitment.target.cycle
        let commitmentID = commitment.persistentModelID
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

    /// Calculate the date range for the report (i.e. last report date - now)
    ///
    /// Side effect:
    /// reads persisted watermark, and advances it to now.
    ///
    /// Notes:
    /// - If persisted watermark is `0`, this is first app run: establish baseline
    ///   at current psych-day and do not show historical cycles.
    static func reportRange() -> FinishedCycleReportRequest? {
        let previousRef = UserDefaults.standard.double(
            forKey: AppSettings.finishedCycleReportLastShownPsychDayKey
        )
        let nowPsychDay = Time.psychDay(for: Time.now())
        // Persist watermark updates regardless of whether we show anything.
        UserDefaults.standard.set(
            toPsychDayRef(nowPsychDay),
            forKey: AppSettings.finishedCycleReportLastShownPsychDayKey
        )
        // First bootstrap: establish baseline and do not show historical cycles.
        guard previousRef != 0 else { return nil }

        let startPsychDay = fromPsychDayRef(previousRef)
        // No completed cycle is possible if the window has zero width.
        guard startPsychDay < nowPsychDay else { return nil }

        return FinishedCycleReportRequest(
            startPsychDay: startPsychDay,
            endPsychDay: nowPsychDay
        )
    }
}
