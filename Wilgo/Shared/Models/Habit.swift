import Foundation
import SwiftData

// NOTE:
// we only support daily frequencies for now.

enum ProofOfWorkType: String, Codable {
    case manual = "Manual"
    // case notionAPI = "Notion API"
    // case healthKit = "HealthKit"
}

// MARK: - Habit

@Model
final class Habit {
    var title: String
    var createdAt: Date

    /// Historical completion / skip records for this habit.
    @Relationship(deleteRule: .cascade, inverse: \HabitCheckIn.habit)
    var checkIns: [HabitCheckIn] = []

    /// N× daily: each slot has its own ideal window.
    @Relationship(deleteRule: .cascade, inverse: \Slot.habit)
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
    /// Set from the current calendar when the habit is created or when reset rules change.
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

extension Habit {
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
        now: Date = HabitScheduling.now(),
        excluding excluded: [Slot]
    ) -> Slot? {
        return slots.first(where: { slot in
            if excluded.contains(where: { $0 === slot }) {
                return false
            }

            return slot.contains(timeOfDay: now)
        })
    }

    /// The first after time.
    func firstSlotAfter(time: Date = HabitScheduling.now()) -> Slot? {
        return slots.sorted().first(where: {
            time
                <= HabitScheduling.resolve(
                    timeOfDay: $0.start, psychDay: HabitScheduling.psychDay(for: time))
        })
    }

    func hasMetDailyGoal(for psychDay: Date) -> Bool {
        print("hasMetDailyGoal: \(completedCount(for: psychDay)) >= \(goalCountPerDay)")
        return completedCount(for: psychDay) >= goalCountPerDay
    }
}
