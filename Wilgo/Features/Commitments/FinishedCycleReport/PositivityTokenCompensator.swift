import Foundation
import SwiftData

struct PositivityCycleNeed {
    let cycleID: String
    let commitmentID: PersistentIdentifier
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
