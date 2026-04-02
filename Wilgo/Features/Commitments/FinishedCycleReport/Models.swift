import Foundation

struct CommitmentReport: Identifiable {
    let id: String
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
    let aidedByPositivityTokenCount: Int
    let checkIns: [CheckIn]

    var compensatedCheckIns: Int { actualCheckIns + aidedByPositivityTokenCount }
    var metTarget: Bool { compensatedCheckIns >= targetCheckIns }
    var isAidedByPositivityToken: Bool { aidedByPositivityTokenCount > 0 }
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
