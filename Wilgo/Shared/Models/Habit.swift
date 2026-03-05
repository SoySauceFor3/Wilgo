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
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
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
    /// Start of the slot as psychDay of now.
    var startToday: Date { HabitScheduling.today(at: start) }

    /// End of the slot of psychDay of now.
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
            return HabitScheduling.today(at: lhs.end) < HabitScheduling.today(at: rhs.end)
        } else {
            return HabitScheduling.today(at: lhs.start) < HabitScheduling.today(at: rhs.start)
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

    /// Number of allowed skips within the budget period.
    var skipCreditCount: Int
    /// The period over which skip budget resets.
    var skipCreditPeriod: Period

    /// TODO: Verify that the timezone changes are handled correctly.
    /// Anchor date that determines when each period begins.
    ///
    /// - For **weekly**: the period resets on the same weekday as this date, every week.
    /// - For **monthly**: the period resets on the same day-of-month as this date, every
    ///   month, clamped to the last day of shorter months.
    /// - For **daily**: ignored — daily always resets at midnight.
    ///
    /// Set to `createdAt` for new habits. Updated to `Date.now` whenever `skipCreditPeriod`
    /// is changed by the user, so the new period type starts fresh from today.
    ///
    /// `nil` for habits created before this field was introduced; `SkipCreditService`
    /// falls back to `createdAt` when this is nil, preserving the same semantics.
    var periodAnchor: Date
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
        skipCreditPeriod: Period,
        proofOfWorkType: ProofOfWorkType = .manual,
        punishment: String? = nil
    ) {
        self.title = title
        self.createdAt = createdAt
        self.slots = slots
        self.skipCreditCount = skipCreditCount
        self.skipCreditPeriod = skipCreditPeriod
        self.periodAnchor = createdAt
        self.proofOfWorkType = proofOfWorkType
        self.punishment = punishment
    }

    /// Times per day (N× daily). Convenience for display.
    var timesPerDay: Int { slots.count }
}

// MARK: - Slot queries

extension Habit {
    func completedCount(now: Date) -> Int {
        let psychDay = HabitScheduling.psychDay(for: now)
        return checkIns.filter { $0.psychDay == psychDay }.count
    }

    /// Slots not yet completed today (psychological day of now), in schedule order.
    func remainingSlots(now: Date) -> [HabitSlot] {
        return Array(slots.sorted().dropFirst(completedCount(now: now)))
    }

    func unfinishedToday(now: Date) -> Bool {
        !remainingSlots(now: now).isEmpty
    }

    /// The first remaining slot whose window contains `now`, skipping snoozed ones.
    func firstCurrentSlot(now: Date, excluding snoozed: [SnoozedSlot]) -> HabitSlot? {
        remainingSlots(now: now).first { slot in
            !snoozed.contains { $0.habit === self && $0.slot === slot }
                && slot.startToday <= now && now <= slot.endToday
        }
    }

    /// The first remaining slot that hasn't started yet.
    func firstFutureSlot(now: Date) -> HabitSlot? {
        remainingSlots(now: now).first { now <= $0.startToday }
    }
}
