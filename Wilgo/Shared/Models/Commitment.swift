import Foundation
import SwiftData

// NOTE:
// we only support daily frequencies for now.

enum ProofOfWorkType: String, Codable {
    case manual = "Manual"
    // case notionAPI = "Notion API"
    // case healthKit = "HealthKit"
}

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

    /// Target number of completions per psychological day.
    /// If nil, defaults to `max(1, slots.count)` for backwards compatibility.
    var goalCountPerDay: Int

    /// Number of allowed skips within the budget period.
    var skipCreditCount: Int
    /// TODO: Verify that hte timezone changes are handled correctly.
    /// How often the skip-credit budget resets, with the anchor baked in.
    ///
    /// - `.daily`:           resets every midnight; no anchor.
    /// - `.weekly(weekday)`: resets on the given Calendar weekday (1 = Sun … 7 = Sat).
    /// - `.monthly(day)`:    resets on the given day-of-month (1–31), clamped for short months.
    ///
    /// Set from the current calendar when the commitment is created or when reset rules change.
    var cycle: Cycle
    /// How completion is verified.
    var proofOfWorkType: ProofOfWorkType
    /// What the user owes if skip credits are exhausted (e.g. "Give robaroba 20 RMB").
    /// Nil means no punishment is set.
    var punishment: String?

    init(
        title: String,
        createdAt: Date = .now,
        slots: [Slot],
        skipCreditCount: Int,
        cycle: Cycle,
        proofOfWorkType: ProofOfWorkType = .manual,
        punishment: String? = nil,
        goalCountPerDay: Int
    ) {
        self.title = title
        self.createdAt = createdAt
        self.slots = slots
        self.goalCountPerDay = goalCountPerDay
        self.skipCreditCount = skipCreditCount
        self.cycle = cycle
        self.proofOfWorkType = proofOfWorkType
        self.punishment = punishment
    }

    // // TODO: REmove it
    // /// Times per day (N× daily). Convenience for display.
    // var timesPerDay: Int { goalCountPerDay ?? max(1, slots.count) }
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
        return completedCount(for: psychDay) >= goalCountPerDay
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
        if notPassedResolvedSlots.count >= goalCountPerDay - completed {
            return StageStatus(category: .future, nextUpSlots: notPassedResolvedSlots)
        }

        return StageStatus(category: .catchUp, nextUpSlots: notPassedResolvedSlots)
    }
}
