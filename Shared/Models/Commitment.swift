import Foundation
import SwiftData

enum ProofOfWorkType: String, Codable {
    case manual = "Manual"
    // case notionAPI = "Notion API"
    // case healthKit = "HealthKit"
}

struct Target: Codable, Hashable {
    var count: Int  // “how many per that cycle”
    private var mode: TargetMode = .on

    init(count: Int, mode: TargetMode = .on) {
        self.count = count
        self.mode = mode
    }
}

// Legacy code, can be removed and replaced with just `var mode: TargetMode` if needed later
extension Target {
    var configuredMode: TargetMode { mode }

    mutating func setConfiguredMode(_ mode: TargetMode) {
        self.mode = mode
    }
}

// MARK: - Commitment

@Model
final class Commitment {
    @Attribute(.unique)
    var id: UUID
    var title: String
    var createdAt: Date
    /// When the commitment was archived. Nil means the commitment is active.
    var archivedAt: Date?

    /// Historical completion / skip records for this commitment.
    @Relationship(deleteRule: .cascade, inverse: \CheckIn.commitment)
    var checkIns: [CheckIn] = []

    /// N× daily: each slot has its own ideal window.
    @Relationship(deleteRule: .cascade, inverse: \Slot.commitment)
    var slots: [Slot] = []

    /// The time window used for grouping check-ins and triggering cycle reports.
    /// Always present, independent of whether a goal is set.
    var cycle: Cycle
    var target: Target

    /// How completion is verified.
    var proofOfWorkType: ProofOfWorkType
    /// What the user owes if skip credits are exhausted (e.g. "Give robaroba 20 RMB").
    /// Nil means no punishment is set.
    var punishment: String?

    var encouragements: [String] = []

    @Relationship(deleteRule: .nullify, inverse: \Tag.commitments)
    var tags: [Tag] = []  // nullify: deleting a Tag removes it from this array; Commitment survives

    @Relationship(deleteRule: .cascade, inverse: \CycleRecord.commitment)
    var cycleRecords: [CycleRecord] = []

    /// When false, this commitment is excluded from Stage reminders and CatchUpReminder notifications.
    var isRemindersEnabled: Bool = true

    /// When true, reminders keep firing even after the daily goal has been met.
    var continueRemindersAfterGoalMet: Bool = false

    init(
        title: String,
        createdAt: Date = .now,
        cycle: Cycle,
        slots: [Slot],
        target: Target,
        proofOfWorkType: ProofOfWorkType = .manual,
        punishment: String? = nil,
        isRemindersEnabled: Bool = true,
        continueRemindersAfterGoalMet: Bool = false,
    ) {
        self.id = UUID()
        self.title = title
        self.createdAt = createdAt
        self.cycle = cycle
        self.slots = slots
        self.target = target
        self.proofOfWorkType = proofOfWorkType
        self.punishment = punishment
        self.isRemindersEnabled = isRemindersEnabled
        self.continueRemindersAfterGoalMet = continueRemindersAfterGoalMet
    }

    // checkins of a commitment in a given psych-day range [startPsychDay, endPsychDay)
    func checkInsInRange(startPsychDay: Date, endPsychDay: Date) -> [CheckIn] {
        let checkInsInRange = checkIns.filter {
            $0.psychDay >= startPsychDay && $0.psychDay < endPsychDay
        }
        return checkInsInRange.sorted { $0.createdAt < $1.createdAt }
    }

    /// Check-ins falling in the target cycle that contains `day`, sorted by `createdAt`.
    /// Uses the half-open cycle range `[start, exclusiveEnd)` — the same window the status engine
    /// (`goalProgress`) counts against, so UI counts stay consistent with goal-met logic.
    func checkInsInCycle(containing day: Date = Time.now()) -> [CheckIn] {
        let bounds = cycle.bounds(including: day)
        return checkInsInRange(startPsychDay: bounds.start, endPsychDay: bounds.end)
    }

}
