import Foundation
import SwiftData

enum ProofOfWorkType: String, Codable {
    case manual = "Manual"
    // case notionAPI = "Notion API"
    // case healthKit = "HealthKit"
}

struct QuantifiedCycle: Codable, Hashable {
    var count: Int  // “how many per that cycle”
    var isEnabled: Bool = true
}

typealias Target = QuantifiedCycle

// MARK: - Commitment

@Model
final class Commitment {
    @Attribute(.unique)
    var id: UUID
    var title: String
    var createdAt: Date

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

    /// Grace periods during which cycles are exempt from penalty and PT evaluation.
    /// Appended at creation (user opts in for partial first cycle) or on rule edits
    /// (user chooses a grace period for the current cycle). See `GracePeriod`.
    var gracePeriods: [GracePeriod] = []

    var encouragements: [String] = []

    @Relationship(deleteRule: .nullify, inverse: \Tag.commitments)
    var tags: [Tag] = []  // nullify: deleting a Tag removes it from this array; Commitment survives

    /// When false, this commitment is excluded from Stage reminders and CatchUpReminder notifications.
    var isRemindersEnabled: Bool = true

    init(
        title: String,
        createdAt: Date = .now,
        cycle: Cycle,
        slots: [Slot],
        target: Target,
        proofOfWorkType: ProofOfWorkType = .manual,
        punishment: String? = nil,
        isRemindersEnabled: Bool = true,
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
    }

    // checkins of a commitment in a given psych-day range [startPsychDay, endPsychDay)
    func checkInsInRange(startPsychDay: Date, endPsychDay: Date) -> [CheckIn] {
        let checkInsInRange = checkIns.filter {
            $0.psychDay >= startPsychDay && $0.psychDay < endPsychDay
        }
        return checkInsInRange.sorted { $0.createdAt < $1.createdAt }
    }
}

// MARK: - Slot queries

extension Commitment {
    private typealias ResolvedSlotPair = (occurrence: Slot, original: Slot)

    func checkInsInCycle(
        cycle: Cycle,
        until psychDay: Date = Time.startOfDay(for: Time.now()),
        inclusive: Bool = true
    ) -> [CheckIn] {
        let start = cycle.startDayOfCycle(including: psychDay)
        return checkIns.filter {
            start <= $0.psychDay && (inclusive ? $0.psychDay <= psychDay : $0.psychDay < psychDay)
        }
    }

    // MARK: - Stage categorization

    enum StageCategory {
        case metGoal
        case current
        case future
        case catchUp
        case others
    }

    struct StageStatus {
        let category: StageCategory
        /// All unfinished slots whose windows have not yet ended in the target cycle, sorted.
        /// Includes the current slot (if any) and any later slots.
        /// IMPORTANT: it contains date info, not just time of day.
        let nextUpSlots: [Slot]
        /// Minimal number of extra check-ins that must be done
        /// outside the remaining scheduled slots in this cycle
        /// in order to still hit the target.
        let behindCount: Int
    }

    private func resolvedSlotPairs(
        from startDay: Date,
        until endDay: Date,
        includeCarryOver: Bool = true,
        calendar: Calendar = Time.calendar
    ) -> [ResolvedSlotPair] {
        var pairs: [ResolvedSlotPair] = []

        if includeCarryOver,
            let previousDay = calendar.date(byAdding: .day, value: -1, to: startDay)
        {
            for slot in slots {
                guard let occurrence = slot.resolveOccurrence(on: previousDay) else { continue }
                guard occurrence.end > startDay else { continue }
                pairs.append((occurrence: occurrence, original: slot))
            }
        }

        var dayCursor = startDay
        while dayCursor < endDay {
            for slot in slots {
                guard let occurrence = slot.resolveOccurrence(on: dayCursor) else { continue }
                pairs.append((occurrence: occurrence, original: slot))
            }
            dayCursor = calendar.date(byAdding: .day, value: 1, to: dayCursor) ?? endDay
        }

        pairs.sort {
            let lhs = $0.occurrence
            let rhs = $1.occurrence
            if lhs.start == rhs.start { return lhs.end < rhs.end }
            return lhs.start < rhs.start
        }
        return pairs
    }

    private func remainingUsableOccurrences(
        in pairs: [ResolvedSlotPair],
        now: Date,
        checkIns: [CheckIn]
    ) -> [Slot] {
        pairs.compactMap { pair in
            guard pair.occurrence.end >= now else { return nil }
            guard pair.occurrence.start <= now else { return pair.occurrence }
            guard !pair.original.isSnoozed(at: now) else { return nil }
            guard !pair.original.isSaturated(at: now, checkIns: checkIns) else { return nil }
            return pair.occurrence
        }
    }

    /// Classifies this commitment for the current psychological day at the given time.
    ///
    /// Precedence:
    /// - `metGoal`: if cycle's goal already met.
    /// - `current`: elif there is a slot whose window contains `now`.
    /// - `future`: elif there are slots within the today (psych day)
    /// - `catchUp`: elif the count of remaining slots < leftToDo.
    /// - `others`: all other cases.
    func stageStatus(
        now: Date = Time.now()
    ) -> StageStatus {
        if !target.isEnabled {
            return targetDisabledStatus(now: now)
        }

        let target = self.target
        let nowPsychDay = Time.startOfDay(for: now)
        let startDay = cycle.startDayOfCycle(including: nowPsychDay)
        let endDay = cycle.endDayOfCycle(including: nowPsychDay)
        let checkInsInCycle = checkInsInRange(startPsychDay: startDay, endPsychDay: endDay)
        let leftToDo = max(0, target.count - checkInsInCycle.count)

        if leftToDo == 0 {
            return StageStatus(category: .metGoal, nextUpSlots: [], behindCount: 0)
        }

        // Get all slot occurrences in the target cycle (with concrete datetimes), then sort.
        // Each entry pairs the resolved occurrence with the original Slot model (for snooze checks).
        let remainingSlots = remainingUsableOccurrences(
            in: resolvedSlotPairs(from: startDay, until: endDay),
            now: now,
            checkIns: checkInsInCycle
        )
        let behindCount = max(0, leftToDo - remainingSlots.count)

        // If there is slot overlapping with now, it's current.
        if let first = remainingSlots.first, first.start <= now {
            return StageStatus(
                category: .current,
                nextUpSlots: remainingSlots,
                behindCount: behindCount
            )
        }

        // Else if there is slot in the rest of the psych-day, it's future.
        let todayEnd =
            Time.calendar.date(byAdding: .day, value: 1, to: nowPsychDay) ?? nowPsychDay
        if remainingSlots.contains(where: { $0.start < todayEnd }) {
            return StageStatus(
                category: .future,
                nextUpSlots: remainingSlots,
                behindCount: behindCount
            )
        }

        // If the count of remaining slots < leftToDo, it's catchUp. Else it's others.
        let category: StageCategory = behindCount > 0 ? .catchUp : .others
        return StageStatus(
            category: category,
            nextUpSlots: remainingSlots,
            behindCount: behindCount
        )
    }

    private func targetDisabledStatus(now: Date) -> StageStatus {
        let nowPsychDay = Time.startOfDay(for: now)

        let todayEnd = Time.calendar.date(byAdding: .day, value: 1, to: nowPsychDay) ?? nowPsychDay
        let remaining = remainingUsableOccurrences(
            in: resolvedSlotPairs(from: nowPsychDay, until: todayEnd),
            now: now,
            checkIns: checkIns
        )

        guard let first = remaining.first else {
            return StageStatus(category: .others, nextUpSlots: [], behindCount: 0)
        }

        if first.start <= now {
            return StageStatus(category: .current, nextUpSlots: remaining, behindCount: 0)
        }
        return StageStatus(category: .future, nextUpSlots: remaining, behindCount: 0)
    }
}
