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
    ) -> [String: [String]] {
        guard monthlyCap > 0 else { return [:] }

        var activeTokens = tokens.filter { token in
            token.status == .active
        }
        .sorted { $0.createdAt < $1.createdAt }

        guard !activeTokens.isEmpty else { return [:] }

        var usageCountByMonth = usedCountByMonth(from: tokens, calendar: calendar)
        var consumedReasonsByCycleID: [String: [String]] = [:]

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
                consumedReasonsByCycleID[need.cycleID, default: []].append(token.reason)
                compensated += 1
                usageCountByMonth[monthKey, default: 0] += 1
            }
        }

        return consumedReasonsByCycleID
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

    static func positivityTokenMonthlyCap() -> Int {
        let value: Int
        if UserDefaults.standard.object(forKey: AppSettings.positivityTokenMonthlyCapKey) == nil {
            value = monthlyCapDefault
        } else {
            value = UserDefaults.standard.integer(forKey: AppSettings.positivityTokenMonthlyCapKey)
        }
        return max(0, value)
    }

    static func usageSummary(
        preReport: [CommitmentReport],
        finalReport: [CommitmentReport],
        allTokens: [PositivityToken],
        monthlyCap: Int? = nil,
        calendar: Calendar = Time.calendar
    ) -> PositivityTokenUsageSummary {
        let totalTokensUsed = finalReport
            .flatMap(\.cycles)
            .reduce(0) { $0 + $1.aidedByPositivityTokenCount }
        let activeTokensAfter = allTokens.filter { $0.status == .active }.count
        let availableBudgetAfter = reportBudgetAvailable(
            for: preReport,
            allTokens: allTokens,
            monthlyCap: monthlyCap ?? positivityTokenMonthlyCap(),
            calendar: calendar
        )

        return PositivityTokenUsageSummary(
            activeTokensBefore: activeTokensAfter + totalTokensUsed,
            activeTokensAfter: activeTokensAfter,
            availableBudgetBefore: availableBudgetAfter + totalTokensUsed,
            availableBudgetAfter: availableBudgetAfter,
            totalTokensUsed: totalTokensUsed
        )
    }

    /// Phase 2: takes a pre-token report and returns a new report with positivity
    /// token compensation applied — populating each cycle's `consumedPTReasons`.
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
                // Target-disabled cycles are also exempt: the user has no target to compensate.
                guard !cycle.isGrace, cycle.isTargetEnabled else { return nil }
                return PositivityCycleNeed(
                    cycleID: cycle.id,
                    commitmentID: commitmentReport.commitment.id,
                    cycleEndPsychDay: cycle.cycleEndPsychDay,
                    missingCheckIns: max(0, cycle.targetCheckIns - cycle.actualCheckIns)
                )
            }
        }
        let reasonsByCycleID = PositivityTokenCompensator.apply(
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
                        consumedPTReasons: reasonsByCycleID[cycle.id, default: []],
                        checkIns: cycle.checkIns,
                        isGrace: cycle.isGrace,
                        isTargetEnabled: cycle.isTargetEnabled
                    )
                }
            )
        }
        return updatedCommitments
    }

    private static func reportBudgetAvailable(
        for report: [CommitmentReport],
        allTokens: [PositivityToken],
        monthlyCap: Int,
        calendar: Calendar
    ) -> Int {
        guard monthlyCap > 0 else { return 0 }

        let neededMonthKeys = Set(
            report.flatMap { commitmentReport in
                commitmentReport.cycles.compactMap { cycle -> String? in
                    guard !cycle.isGrace, cycle.isTargetEnabled else { return nil }
                    guard cycle.targetCheckIns > cycle.actualCheckIns else { return nil }
                    let usagePsychDay = previousPsychDay(cycle.cycleEndPsychDay, calendar: calendar)
                    return psychMonthKey(of: usagePsychDay, calendar: calendar)
                }
            }
        )

        guard !neededMonthKeys.isEmpty else { return 0 }

        let usedCountByMonth = usedCountByMonth(from: allTokens, calendar: calendar)
        return neededMonthKeys.reduce(0) { total, monthKey in
            total + max(0, monthlyCap - usedCountByMonth[monthKey, default: 0])
        }
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
