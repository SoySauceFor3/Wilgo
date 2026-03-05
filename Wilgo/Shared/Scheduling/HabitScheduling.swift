//  Reusable scheduling and "today" time helpers for habits.
//  Schedule is N× daily only (for now); each occurrence has one slot with its own ideal window.

import Foundation

/// Shared scheduling and calendar utilities for habits.
enum HabitScheduling {
    static let calendar = Calendar.current

    /// Returns the current date. Override in tests to freeze time.
    /// Production code must never call `Date()` directly — use `HabitScheduling.now()` instead.
    static var now: () -> Date = { Date() }

    /// Hour of day when a "psych day" starts. Reads live from UserDefaults so it
    /// always reflects the value the user last set in Settings without a restart.
    static var dayStartHourOffset: Int {
        let stored = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)
        // integer(forKey:) returns 0 when the key is absent, which is our desired default.
        return stored
    }

    /// Resolves a habit's time-of-day `Date` to its concrete `Date` within the
    /// current psychDay, accounting for `dayStartHourOffset`.
    ///
    /// Example: `dayStartHourOffset` = 14 (2 pm). The logical day runs Jan 1 2 pm → Jan 2 2 pm.
    /// Passing a 2 am time-of-day while the real clock reads Jan 1 returns Jan 2 02:00,
    /// because 2 am sits in the overnight tail of that same psych day.
    ///
    /// With the default offset of 0 this behaves identically to stamping the time on today.
    static func today(
        at timeOfDay: Date,  // Only take hour and minute from this
        now: Date = now(),
        dayStartHourOffset: Int = dayStartHourOffset
    ) -> Date {
        // Calendar date on which the current psychDay *started*.
        // If we haven't reached the day-start hour yet, the psych day began yesterday.
        let psychDay = psychDay(for: now, dayStartHourOffset: dayStartHourOffset)

        // Times >= offset fall on the psych-day-start calendar date.
        // Times < offset are in the overnight tail and fall on the following calendar date.
        let timeHour = calendar.component(.hour, from: timeOfDay)
        let timeMinute = calendar.component(.minute, from: timeOfDay)
        let baseDate: Date
        if timeHour >= dayStartHourOffset {
            baseDate = psychDay
        } else {
            baseDate = calendar.date(byAdding: .day, value: 1, to: psychDay)!
        }

        return calendar.date(
            bySettingHour: timeHour,
            minute: timeMinute,
            second: 0,
            of: baseDate
        ) ?? baseDate
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

}
