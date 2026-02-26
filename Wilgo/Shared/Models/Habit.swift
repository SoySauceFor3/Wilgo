import Foundation
import SwiftData

// NOTE: 
// we only support daily frequencies for now. 

enum ProofOfWorkType: String, Codable {
    case manual = "Manual"
    // case notionAPI = "Notion API"
    // case healthKit = "HealthKit"
}

enum Period: String, Codable {
    case daily   = "Daily"
    case weekly  = "Weekly"
    case monthly = "Monthly"
}

// MARK: - HabitSlot (one ideal window per occurrence, for N× daily)

@Model
final class HabitSlot {
    /// Start of this slot's ideal window (time-of-day only, arbitrary reference day).
    var start: Date
    /// End of this slot's ideal window (time-of-day only).
    var end: Date
    /// Order of this slot in the day (0 = first, 1 = second, …).
    var sortOrder: Int

    @Relationship var habit: Habit?

    init(
        start: Date,
        end: Date,
        sortOrder: Int
    ) {
        self.start = start
        self.end = end
        self.sortOrder = sortOrder
    }
}

// MARK: - Habit

@Model
final class Habit {
    var title: String
    var createdAt: Date

    /// Historical completion / skip records for this habit (per slot, see HabitCheckIn.slotIndex).
    @Relationship(deleteRule: .cascade, inverse: \HabitCheckIn.habit)
    var checkIns: [HabitCheckIn] = []

    /// N× daily: each slot has its own ideal window. Order by HabitSlot.sortOrder.
    @Relationship(deleteRule: .cascade, inverse: \HabitSlot.habit)
    var slots: [HabitSlot] = []

    /// Number of allowed skips within the budget period.
    var skipCreditCount: Int
    /// The period over which skip budget resets.
    var skipCreditPeriod: Period
    /// How completion is verified.
    var proofOfWorkType: ProofOfWorkType

    init(
        title: String,
        createdAt: Date = .now,
        slots: [HabitSlot],
        skipCreditCount: Int,
        skipCreditPeriod: Period,
        proofOfWorkType: ProofOfWorkType = .manual
    ) {
        self.title = title
        self.createdAt = createdAt
        self.slots = slots
        self.skipCreditCount = skipCreditCount
        self.skipCreditPeriod = skipCreditPeriod
        self.proofOfWorkType = proofOfWorkType
    }

    /// Times per day (N× daily). Convenience for display.
    var timesPerDay: Int { slots.count }
}
