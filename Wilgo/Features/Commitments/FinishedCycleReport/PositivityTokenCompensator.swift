import Foundation
import SwiftData

struct PositivityCycleNeed {
    let cycleID: String
    let commitmentID: UUID
    let cycleEndPsychDay: Date
    let missingCheckIns: Int
}

enum PositivityTokenCompensator {
    static func apply(
        cycleNeeds: [PositivityCycleNeed],
        tokens: [PositivityToken],
        monthlyCap: Int,
        calendar: Calendar = Time.calendar
    ) -> [String: Int] {
        guard monthlyCap > 0 else { return [:] }

        var activeTokens = tokens.filter { token in
            token.status == .active
        }
        .sorted { $0.createdAt < $1.createdAt }

        guard !activeTokens.isEmpty else { return [:] }

        var usageCountByMonth = usedCountByMonth(from: tokens, calendar: calendar)
        var aidedByCycleID: [String: Int] = [:]

        let sortedNeeds =
            cycleNeeds
            .filter { $0.missingCheckIns > 0 }
            .sorted {
                if $0.cycleEndPsychDay != $1.cycleEndPsychDay {
                    return $0.cycleEndPsychDay < $1.cycleEndPsychDay
                }
                if $0.commitmentID != $1.commitmentID {
                    return $0.commitmentID < $1.commitmentID
                }
                return $0.cycleID < $1.cycleID
            }

        for need in sortedNeeds {
            guard !activeTokens.isEmpty else { break }
            let usagePsychDay = previousPsychDay(need.cycleEndPsychDay, calendar: calendar)
            let monthKey = psychMonthKey(of: usagePsychDay, calendar: calendar)
            if usageCountByMonth[monthKey, default: 0] >= monthlyCap {
                continue
            }

            var compensated = 0
            while compensated < need.missingCheckIns && !activeTokens.isEmpty {
                if usageCountByMonth[monthKey, default: 0] >= monthlyCap {
                    break
                }
                let token = activeTokens.removeFirst()
                token.status = .used
                token.dayOfStatus = usagePsychDay
                compensated += 1
                usageCountByMonth[monthKey, default: 0] += 1
            }

            if compensated > 0 {
                aidedByCycleID[need.cycleID, default: 0] += compensated
            }
        }

        return aidedByCycleID
    }

    private static func usedCountByMonth(
        from tokens: [PositivityToken],
        calendar: Calendar
    ) -> [String: Int] {
        var result: [String: Int] = [:]
        for token in tokens {
            if token.status == .used, let usedAtPsychDay = token.dayOfStatus {
                let key = psychMonthKey(of: usedAtPsychDay, calendar: calendar)
                result[key, default: 0] += 1
            }
        }
        return result
    }

    private static func previousPsychDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -1, to: date) ?? date
    }

    private static func psychMonthKey(of psychDay: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: psychDay)
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }
}

enum AfterPositivityTokenReportBuilder {
    private static let monthlyCapDefault = 5

    private static func positivityTokenMonthlyCap() -> Int {
        let value: Int
        if UserDefaults.standard.object(forKey: AppSettings.positivityTokenMonthlyCapKey) == nil {
            value = monthlyCapDefault
        } else {
            value = UserDefaults.standard.integer(forKey: AppSettings.positivityTokenMonthlyCapKey)
        }
        return max(0, value)
    }

    /// Phase 2: takes a pre-token report and returns a new report with positivity
    /// token compensation applied to each cycle's `aidedByPositivityTokenCount`.
    static func apply(
        to report: [CommitmentReport],
        allTokens: [PositivityToken],
        monthlyCap: Int? = nil
    ) -> [CommitmentReport] {
        guard !report.isEmpty else { return report }
        let cap = monthlyCap ?? positivityTokenMonthlyCap()
        let cycleNeeds = report.flatMap { commitmentReport in
            commitmentReport.cycles.compactMap { cycle -> PositivityCycleNeed? in
                // Grace cycles are exempt: no PT consumed, monthly cap unaffected.
                guard !cycle.isGrace else { return nil }
                return PositivityCycleNeed(
                    cycleID: cycle.id,
                    commitmentID: commitmentReport.commitment.id,
                    cycleEndPsychDay: cycle.cycleEndPsychDay,
                    missingCheckIns: max(0, cycle.targetCheckIns - cycle.actualCheckIns)
                )
            }
        }
        let aidedTokenCountByCycleID = PositivityTokenCompensator.apply(
            cycleNeeds: cycleNeeds,
            tokens: allTokens,
            monthlyCap: cap,
        )
        let updatedCommitments = report.map { commitmentReport in
            CommitmentReport(
                id: commitmentReport.id,
                commitment: commitmentReport.commitment,
                cycles: commitmentReport.cycles.map { cycle in
                    CycleReport(
                        id: cycle.id,
                        actualCheckIns: cycle.actualCheckIns,
                        targetCheckIns: cycle.targetCheckIns,
                        cycleLabel: cycle.cycleLabel,
                        cycleStartPsychDay: cycle.cycleStartPsychDay,
                        cycleEndPsychDay: cycle.cycleEndPsychDay,
                        aidedByPositivityTokenCount: aidedTokenCountByCycleID[cycle.id, default: 0],
                        checkIns: cycle.checkIns,
                        isGrace: cycle.isGrace
                    )
                }
            )
        }
        return updatedCommitments
    }
}
