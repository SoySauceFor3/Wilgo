import Foundation
import SwiftData

// NOTE:
// we only support daily frequencies for now.

enum ProofOfWorkType: String, Codable {
    case manual = "Manual"
    // case notionAPI = "Notion API"
    // case healthKit = "HealthKit"
}

// MARK: - HabitSlot (one ideal window per occurrence, for N× daily)

@Model
final class HabitSlot {
    /// Start of this slot's ideal window (time-of-day only, arbitrary reference day).
    var start: Date
    /// End of this slot's ideal window (time-of-day only).
    var end: Date

    @Relationship var habit: Habit?

    init(
        start: Date,
        end: Date
    ) {
        self.start = start
        self.end = end
    }
}

extension HabitSlot {
    /// Start of the slot mapped onto the current psychological day.
    var startToday: Date { HabitScheduling.today(at: start) }

    /// End of the slot mapped onto the current psychological day.
    var endToday: Date { HabitScheduling.today(at: end) }

    var slotTimeText: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }
}

extension HabitSlot: Comparable {
    static func < (lhs: HabitSlot, rhs: HabitSlot) -> Bool {
        if lhs.start == rhs.start {
            return lhs.endToday < rhs.endToday
        } else {
            return lhs.startToday < rhs.startToday
        }
    }

    static func == (lhs: HabitSlot, rhs: HabitSlot) -> Bool {
        lhs.start == rhs.start && lhs.end == rhs.end
    }
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
    @Relationship(deleteRule: .cascade, inverse: \HabitSlot.habit)
    var slots: [HabitSlot] = []

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
        slots: [HabitSlot],
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
        return checkIns.filter { $0.psychDay == psychDay }.count
    }

    /// Slots not yet completed on the given psychological day, in order.
    func unfinishedSlots(for psychDay: Date) -> [HabitSlot] {
        return Array(slots.sorted().dropFirst(completedCount(for: psychDay)))
    }

    /// The first remaining slot whose window contains `now`, skipping snoozed ones.
    func firstCurrentSlot(
        now: Date = HabitScheduling.now(),
        excluding snoozed: [SnoozedSlot]
    ) -> HabitSlot? {
        let psychDay = HabitScheduling.psychDay(for: now)
        return unfinishedSlots(for: psychDay).first { slot in
            !snoozed.contains { $0.habit === self && $0.slot === slot }
                && slot.startToday <= now && now <= slot.endToday
        }
    }

    /// The first remaining slot that hasn't started yet.
    func firstFutureSlot(now: Date = HabitScheduling.now()) -> HabitSlot? {
        let psychDay = HabitScheduling.psychDay(for: now)
        return unfinishedSlots(for: psychDay).first { now <= $0.startToday }
    }

    func hasMetDailyGoal(for psychDay: Date) -> Bool {
        print("hasMetDailyGoal: \(completedCount(for: psychDay)) >= \(goalCountPerDay)")
        return completedCount(for: psychDay) >= goalCountPerDay
    }
}
