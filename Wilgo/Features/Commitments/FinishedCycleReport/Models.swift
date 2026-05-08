import Foundation

struct CommitmentReport: Identifiable {
    let id: UUID
    let commitment: Commitment
    let cycles: [CycleReport]
}

struct CycleReport: Identifiable {
    let id: String
    let actualCheckIns: Int
    let targetCheckIns: Int
    let cycleLabel: String
    let cycleStartPsychDay: Date  // inclusive
    let cycleEndPsychDay: Date  // exclusive
    let consumedPTReasons: [String]  // empty when not aided by PT
    let checkIns: [CheckIn]
    /// Effective target mode for this finished cycle. This is resolved from the
    /// stored `TargetMode` and the cycle date range, so non-normalized expired
    /// Inspiration Only modes still report later cycles as `.on`.
    let effectiveTargetMode: TargetMode

    var aidedByPositivityTokenCount: Int { consumedPTReasons.count }
    var compensatedCheckIns: Int { actualCheckIns + aidedByPositivityTokenCount }
    var metTarget: Bool { compensatedCheckIns >= targetCheckIns }
    var isAidedByPositivityToken: Bool { aidedByPositivityTokenCount > 0 }
}

struct PositivityTokenUsageSummary {
    let activeTokensBefore: Int
    let activeTokensAfter: Int
    let availableBudgetBefore: Int
    let availableBudgetAfter: Int
    let totalTokensUsed: Int
}

/// A lightweight token passed to `FinishedCycleReportView` that captures the
/// date window for the report.  The sheet re-derives the full report live from
/// `@Query` sources, so backfills and other data changes are reflected
/// automatically without any parent involvement.
struct FinishedCycleReportRequest: Identifiable {
    let id = UUID()
    let startPsychDay: Date  // inclusive
    let endPsychDay: Date  // exclusive
}
