//  Reusable scheduling and "today" time helpers for habits.
//  Schedule is N× daily only (for now); each occurrence has one slot with its own ideal window.
//

import Foundation

/// Shared scheduling and calendar utilities for habits.
enum HabitScheduling {
    static let calendar = Calendar.current
    static let config = PhaseConfig.default
    /// Hour of day when a "habit day" starts (0 = midnight).
    /// TODO: Can be made user-configurable later.
    static let dayStartHourOffset: Int = 0

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

    /// Logical "psychological day" for a given moment, using the specified time zone and day-start offset.
    /// The result is a Date pinned to the start of that psychological day.
    static func psychDay(
        for utcTime: Date,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        dayStartHourOffset: Int = dayStartHourOffset
    ) -> Date {
        var cal = calendar
        cal.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? calendar.timeZone

        // Shift back by the day-start offset before taking the calendar day.
        let shifted = utcTime.addingTimeInterval(TimeInterval(-dayStartHourOffset * 60 * 60))
        let comps = cal.dateComponents([.year, .month, .day], from: shifted)
        return cal.date(from: comps) ?? utcTime
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

    /// TODO: Remove it.
    /// Window start on the current day for a slot.
    static func windowStartToday(for slot: HabitSlot) -> Date {
        today(at: slot.start)
    }

    /// TODO: Remove it.
    /// Window end on the current day for a slot.
    static func windowEndToday(for slot: HabitSlot) -> Date {
        today(at: slot.end)
    }

    /// Convenient "today" psychological day for now (using current time zone).
    static func todayPsychDay(now: Date = Date()) -> Date {
        psychDay(for: now)
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
