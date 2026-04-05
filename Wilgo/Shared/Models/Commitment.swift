import Foundation
import SwiftData

enum ProofOfWorkType: String, Codable {
    case manual = "Manual"
    // case notionAPI = "Notion API"
    // case healthKit = "HealthKit"
}

struct QuantifiedCycle: Codable, Hashable {
    var cycle: Cycle  // daily / weekly / monthly with anchors
    var count: Int  // “how many per that cycle”
}

typealias Target = QuantifiedCycle
typealias SkipBudget = QuantifiedCycle

// MARK: - Commitment

@Model
final class Commitment {
    var title: String
    var createdAt: Date

    /// Historical completion / skip records for this commitment.
    @Relationship(deleteRule: .cascade, inverse: \CheckIn.commitment)
    var checkIns: [CheckIn] = []

    /// N× daily: each slot has its own ideal window.
    @Relationship(deleteRule: .cascade, inverse: \Slot.commitment)
    var slots: [Slot] = []

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

    init(
        title: String,
        createdAt: Date = .now,
        slots: [Slot],
        target: Target,
        skipBudget: SkipBudget,
        proofOfWorkType: ProofOfWorkType = .manual,
        punishment: String? = nil,
    ) {
        self.title = title
        self.createdAt = createdAt
        self.slots = slots
        self.target = target
        self.proofOfWorkType = proofOfWorkType
        self.punishment = punishment
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
    /// Number of check-ins on the given psychological day.
    func completedCount(for psychDay: Date) -> Int {
        return checkIns.filter({ $0.psychDay == psychDay }).count
    }

    /// Slots not yet completed on the given psychological day, in order.
    func unfinishedSlots(for psychDay: Date) -> [Slot] {
        return Array(slots.sorted().dropFirst(completedCount(for: psychDay)))
    }

    /// The first slot whose window overlaps with `now`, skipping excluded ones.
    func firstCurrentSlot(
        now: Date = Time.now(),
        excluding excluded: [Slot]
    ) -> Slot? {
        return slots.first(where: { slot in
            if excluded.contains(where: { $0 === slot }) {
                return false
            }

            return slot.contains(timeOfDay: now)
        })
    }

    /// The first slot after `time`.
    func firstSlotAfter(time: Date = Time.now()) -> Slot? {
        return slots.sorted().first(where: {
            time
                <= Time.resolve(
                    timeOfDay: $0.start, psychDay: Time.psychDay(for: time))
        })
    }

    func hasMetDailyGoal(for psychDay: Date) -> Bool {
        // TODO: THIS NEED TO CHANGED!!!!!!!!!!!!!!!!
        return completedCount(for: psychDay) >= target.count
    }

    func checkInsInCycle(
        cycle: Cycle,
        until psychDay: Date = Time.psychDay(for: Time.now()),
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

    /// TODO: THIS NEED TO CHANGED!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
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
        let target = self.target
        let nowPsychDay = Time.psychDay(for: now)
        let startDay = target.cycle.startDayOfCycle(including: nowPsychDay)
        let endDay = target.cycle.endDayOfCycle(including: nowPsychDay)
        let checkInsInCycle = checkInsInRange(startPsychDay: startDay, endPsychDay: endDay)
        let leftToDo = max(0, target.count - checkInsInCycle.count)

        if leftToDo == 0 {
            return StageStatus(category: .metGoal, nextUpSlots: [], behindCount: 0)
        }

        let cal = Time.calendar

        func psychDayStartTime(_ psychDay: Date) -> Date {
            // psychDay is pinned to midnight; real day start is midnight + offset.
            psychDay.addingTimeInterval(
                TimeInterval(Time.dayStartHourOffset * 3_600))
        }

        func resolveSlotOccurrence(slot: Slot, psychDay: Date) -> Slot? {
            let start = Time.resolve(timeOfDay: slot.start, psychDay: psychDay)
            var end = Time.resolve(timeOfDay: slot.end, psychDay: psychDay)
            if end <= start {
                end = cal.date(byAdding: .day, value: 1, to: end) ?? end
            }

            // Respect recurrence (if any). Evaluate at the concrete start time.
            guard slot.isActive(on: start, calendar: cal) else { return nil }

            // IMPORTANT: This Slot carries concrete datetimes in start/end.
            return Slot(start: start, end: end)
        }

        // Get all slot occurrences in the target cycle (with concrete datetimes), then sort.
        var resolvedOccurrences: [Slot] = []
        var dayCursor = startDay
        while dayCursor < endDay {
            for slot in slots {
                if let occurrence = resolveSlotOccurrence(slot: slot, psychDay: dayCursor) {
                    resolvedOccurrences.append(occurrence)
                }
            }
            dayCursor = cal.date(byAdding: .day, value: 1, to: dayCursor) ?? endDay
        }

        resolvedOccurrences.sort {
            if $0.start == $1.start { return $0.end < $1.end } else { return $0.start < $1.start }
        }

        // Remaining slot occurrences in the cycle that have not yet ended.
        let remainingInCycle: [Slot]
        if let firstNotEndedIndex = resolvedOccurrences.firstIndex(where: { $0.end >= now }) {
            remainingInCycle = Array(resolvedOccurrences[firstNotEndedIndex...])
        } else {
            remainingInCycle = []
        }

        let remainingSlotsCount = remainingInCycle.count
        let behindCount = max(0, leftToDo - remainingSlotsCount)

        // If there is slot overlapping with now, it's current.
        if let first = remainingInCycle.first, first.start <= now {
            return StageStatus(
                category: .current,
                nextUpSlots: remainingInCycle,
                behindCount: behindCount
            )
        }

        // Else if there is slot in the rest of the psych-day, it's future.
        let todayStart = psychDayStartTime(nowPsychDay)
        let todayEnd = todayStart.addingTimeInterval(24 * 60 * 60)
        let hasSlotInRestOfPsychDay = remainingInCycle.contains { $0.start < todayEnd }
        if hasSlotInRestOfPsychDay {
            return StageStatus(
                category: .future,
                nextUpSlots: remainingInCycle,
                behindCount: behindCount
            )
        }

        // If the count of remaining slots < leftToDo, it's catchUp. Else it's others.
        if remainingSlotsCount < leftToDo {
            return StageStatus(
                category: .catchUp,
                nextUpSlots: remainingInCycle,
                behindCount: behindCount
            )
        }

        return StageStatus(
            category: .others,
            nextUpSlots: remainingInCycle,
            behindCount: behindCount
        )
    }
}
