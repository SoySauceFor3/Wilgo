//  Reusable scheduling and "today" time helpers for habits.
//  Schedule is N× daily only (for now); each occurrence has one slot with its own ideal window.
//

import Foundation

/// Shared scheduling and calendar utilities for habits.
enum HabitScheduling {
    static let calendar = Calendar.current
    static let config = PhaseConfig.default

    /// Resolves a habit's time-of-day `Date` to today's date with that time.
    static func today(at timeOfDay: Date) -> Date {
        let comps = calendar.dateComponents([.hour, .minute], from: timeOfDay)
        return calendar.date(
            bySettingHour: comps.hour ?? 0,
            minute: comps.minute ?? 0,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    /// Slots for a habit, sorted by window start time today (by sortOrder then idealWindowStart).
    static func sortedSlots(for habit: Habit) -> [HabitSlot] {
        habit.slots.sorted { s1, s2 in
            if s1.sortOrder != s2.sortOrder { return s1.sortOrder < s2.sortOrder }
            return today(at: s1.start) < today(at: s2.start)
        }
    }

    /// Soft deadline for "today": end of day (e.g. midnight as start of next day).
    static func todaySoftDeadline() -> Date {
        var day = calendar.startOfDay(for: Date())
        if config.softDeadlineHour >= 24 {
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            return calendar.date(
                bySettingHour: 0,
                minute: config.softDeadlineMinute,
                second: 0,
                of: day
            ) ?? day
        }
        return calendar.date(
            bySettingHour: config.softDeadlineHour,
            minute: config.softDeadlineMinute,
            second: 0,
            of: day
        ) ?? day
    }

    /// Soft deadline used for ordering (e.g. pick "earliest deadline" among active habits).
    static func softDeadline(for habit: Habit, now: Date = Date()) -> Date {
        todaySoftDeadline()
    }

    /// Window start on the current day for a slot.
    static func windowStartToday(for slot: HabitSlot) -> Date {
        today(at: slot.start)
    }

    /// Window end on the current day for a slot.
    static func windowEndToday(for slot: HabitSlot) -> Date {
        today(at: slot.end)
    }

    /// Whether this slot's window start is still later today (for "upcoming" list).
    static func isUpcomingSlot(_ slot: HabitSlot, now: Date = Date()) -> Bool {
        let windowStart = windowStartToday(for: slot)
        let windowEnd = windowEndToday(for: slot)
        if windowEnd <= windowStart {
            return now < windowStart
        }
        return now < windowStart
    }

    /// Whether `now` falls inside this slot's window today.
    static func isInWindowNow(_ slot: HabitSlot, now: Date = Date()) -> Bool {
        let windowStart = windowStartToday(for: slot)
        let windowEnd = windowEndToday(for: slot)
        if windowEnd <= windowStart {
            return now >= windowStart || now <= windowEnd
        }
        return now >= windowStart && now <= windowEnd
    }

    /// Index in habit.slots (by sortOrder) for the slot whose window contains `now`, or nil if none.
    static func currentSlotIndex(for habit: Habit, now: Date = Date()) -> Int? {
        let sorted = sortedSlots(for: habit)
        guard let idx = sorted.firstIndex(where: { isInWindowNow($0, now: now) }) else { return nil }
        return sorted[idx].sortOrder
    }

    /// First slot (by time) whose window starts after `now` today and hasn't been checked in today.
    static func nextUpcomingSlotIndex(for habit: Habit, now: Date, hasCheckInForSlot: (Int) -> Bool) -> Int? {
        let sorted = sortedSlots(for: habit)
        return sorted.first { slot in
            isUpcomingSlot(slot, now: now) && !hasCheckInForSlot(slot.sortOrder)
        }?.sortOrder
    }

    /// Start of the critical window before today's soft deadline.
    static func criticalStart(now: Date = Date()) -> Date {
        let softDeadline = todaySoftDeadline()
        return calendar.date(
            byAdding: .hour,
            value: -Int(config.criticalWindowHours),
            to: softDeadline
        ) ?? softDeadline
    }
}
