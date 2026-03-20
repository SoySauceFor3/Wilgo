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

        var metTarget: Bool { actualCheckIns >= targetCheckIns }
    }

    let id = UUID()
    let commitments: [CommitmentReport]
}

enum FinishedCycleReportBuilder {
    private static var calendar: Calendar { Time.calendar }

    static func build(
        commitments: [Commitment],
        startPsychDay: Date,  // inclusive
        endPsychDay: Date  // exclusive
    ) -> FinishedCycleReport {
        // let windowStart = startOfPsychDay(startPsychDay)
        // let windowEnd = startOfPsychDay(endPsychDay)

        guard startPsychDay < endPsychDay else {
            return FinishedCycleReport(commitments: [])
        }

        let commitmentReports =
            commitments
            .compactMap { commitmentReport(for: $0, from: startPsychDay, to: endPsychDay) }

        return FinishedCycleReport(commitments: commitmentReports)
    }

    private static func commitmentReport(
        for commitment: Commitment,
        from startPsychDay: Date,  // inclusive
        to endPsychDay: Date  // exclusive
    ) -> FinishedCycleReport.CommitmentReport? {
        let cycles = cyclesForCommitment(for: commitment, from: startPsychDay, to: endPsychDay)
        guard !cycles.isEmpty else { return nil }
        return FinishedCycleReport.CommitmentReport(
            id: commitment.persistentModelID.encoded(),
            commitmentTitle: commitment.title,
            cycles: cycles
        )
    }

    private static func cyclesForCommitment(
        for commitment: Commitment,
        from startPsychDay: Date,  // inclusive
        to endPsychDay: Date  // exclusive
    ) -> [FinishedCycleReport.CycleReport] {
        let cycle = commitment.target.cycle
        var cycleCursorDay = startPsychDay
        var cycles: [FinishedCycleReport.CycleReport] = []

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

            cycles.append(
                FinishedCycleReport.CycleReport(
                    id: reportItemID(for: commitment, cycleEndPsychDay: cycleEnd),
                    actualCheckIns: actualCheckIns,
                    targetCheckIns: commitment.target.count,
                    cycleLabel: cycle.label(of: cycleLabelDay),
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
        now: Date = Time.now()
    ) -> FinishedCycleReport? {
        let previousRef = UserDefaults.standard.double(
            forKey: AppSettings.finishedCycleReportLastShownPsychDayKey
        )
        let nowPsychDay = Time.psychDay(for: now)
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
            endPsychDay: nowPsychDay
        )

        return report.commitments.isEmpty ? nil : report
    }
}
