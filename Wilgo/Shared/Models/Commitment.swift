import Foundation
import SwiftData

enum ProofOfWorkType: String, Codable {
    case manual = "Manual"
    // case notionAPI = "Notion API"
    // case healthKit = "HealthKit"
}

struct QuantifiedCycle: Codable, Hashable {
    var cycle: Cycle  // daily / weekly / monthly with anchors
    var countPerCycle: Int  // “how many per that cycle”
}

typealias Target = QuantifiedCycle  // semantic: target completions per cycle
typealias SkipBudget = QuantifiedCycle  // semantic: forgiven misses per cycle

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

    var skipBudget: SkipBudget

    /// How completion is verified.
    var proofOfWorkType: ProofOfWorkType
    /// What the user owes if skip credits are exhausted (e.g. "Give robaroba 20 RMB").
    /// Nil means no punishment is set.
    var punishment: String?

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
        self.skipBudget = skipBudget
        self.proofOfWorkType = proofOfWorkType
        self.punishment = punishment
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
        now: Date = CommitmentScheduling.now(),
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
    func firstSlotAfter(time: Date = CommitmentScheduling.now()) -> Slot? {
        return slots.sorted().first(where: {
            time
                <= CommitmentScheduling.resolve(
                    timeOfDay: $0.start, psychDay: CommitmentScheduling.psychDay(for: time))
        })
    }

    func hasMetDailyGoal(for psychDay: Date) -> Bool {
        // TODO: THIS NEED TO CHANGED!!!!!!!!!!!!!!!!
        return completedCount(for: psychDay) >= target.countPerCycle
    }

    // MARK: - Stage categorization

    enum StageCategory {
        case metGoal
        case current
        case future
        case catchUp
    }

    struct StageStatus {
        let category: StageCategory
        // /// The slot whose window currently contains `now`, if any.
        // let currentSlot: Slot?
        /// All unfinished slots whose windows have not yet ended today, sorted.
        /// Includes the current slot (if any) and any later slots.
        /// IMPORTANT: it contains date info, not just time of day.
        let nextUpSlots: [Slot]
    }

    /// TODO: THIS NEED TO CHANGED!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    /// Classifies this commitment for the current psychological day at the given time.
    ///
    /// Precedence:
    /// - `metGoal`: today's goal already met.
    /// - `current`: otherwise, if there is a slot whose window contains `now`.
    /// - `future`: otherwise, if remainingNeeded ≤ remainingSlotsToday.count.
    /// - `catchUp`: all other cases.
    func stageStatus(
        now: Date = CommitmentScheduling.now()
    ) -> StageStatus {
        let psychToday = CommitmentScheduling.psychDay(for: now)
        let completed = completedCount(for: psychToday)

        if hasMetDailyGoal(for: psychToday) {
            return StageStatus(category: .metGoal, nextUpSlots: [])
        }

        // To avoid weird bug caused by slots crossing the StartDayHourOffset,
        // resolve slots to their concrete dates and then sort and filter.
        // Also, if there are slots crossing the StartDayHourOffset, we add (yesterday start, today end) and (today start, tomorrow end) to the candidates.
        var candidateResolvedSlots: [Slot] = []  // Important! Here the Slot contains date info, not just time of day.
        for slot in slots {
            let start = slot.startToday
            let end = slot.endToday
            if start > end {
                // means the slot is not crossing the StartDayHourOffset
                candidateResolvedSlots.append(
                    Slot(start: start - TimeInterval(24 * 60 * 60), end: end))
                candidateResolvedSlots.append(
                    Slot(start: start, end: end + TimeInterval(24 * 60 * 60)))
            } else {
                candidateResolvedSlots.append(Slot(start: start, end: end))
            }
        }
        candidateResolvedSlots.sort {
            if $0.start == $1.start { return $0.end < $1.end } else { return $0.start < $1.start }
        }

        let notPassedResolvedSlots = candidateResolvedSlots.filter { now <= $0.end }

        if notPassedResolvedSlots.isEmpty {
            return StageStatus(category: .catchUp, nextUpSlots: [])
        }

        if notPassedResolvedSlots[0].start <= now {
            // now <= notPassedResolvedSlots[0].1 is calculated in the filter step.
            // it means the first element is a current slot.
            return StageStatus(category: .current, nextUpSlots: notPassedResolvedSlots)
        }

        // now < notPassedResolvedSlots[0].0, the first element is a future slot.
        if notPassedResolvedSlots.count >= target.countPerCycle - completed {
            return StageStatus(category: .future, nextUpSlots: notPassedResolvedSlots)
        }

        return StageStatus(category: .catchUp, nextUpSlots: notPassedResolvedSlots)
    }
}
