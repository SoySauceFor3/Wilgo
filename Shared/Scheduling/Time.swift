//  Reusable scheduling and "today" time helpers for commitments.
//  Schedule is N× daily only (for now); each occurrence has one slot with its own ideal window.

import Foundation

/// Shared time, date, and calendar utilities.
enum Time {
    static let calendar = Calendar.current

    /// Returns the current date. Override in tests to freeze time.
    /// Production code must never call `Date()` directly — use `Time.now()` instead.
    static var now: () -> Date = { Date() }

    /// Resolves a time-of-day `Date` to its concrete `Date` within the
    /// current psychDay, accounting for `dayStartHourOffset`.
    ///
    /// Example: `dayStartHourOffset` = 14 (2 pm).
    /// Passing a 2 am time-of-day on Jan 1 psychological day returns Jan 2 02:00,
    /// because 2 am sits in the overnight tail of that same psych day.
    ///
    /// With the default offset of 0 this behaves identically to stamping the time on psychDay.
    static func resolve(
        timeOfDay: Date,  // Only take hour and minute from this
        psychDay: Date = now()
    ) -> Date {
        // Just to make sure psychDay is cleaned up.
        let psychDay = calendar.startOfDay(for: psychDay)
        // Times >= offset fall on the psych-day-start calendar date.
        // Times < offset are in the overnight tail and fall on the following calendar date.
        let timeHour = calendar.component(.hour, from: timeOfDay)
        let timeMinute = calendar.component(.minute, from: timeOfDay)
        let baseDate = psychDay

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
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) -> Date {
        var cal = calendar
        cal.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? calendar.timeZone

        // Shift back by the day-start offset before taking the calendar day.
        let shifted = utcTime
        let comps = cal.dateComponents([.year, .month, .day], from: shifted)
        guard let result = cal.date(from: comps) else {
            fatalError("Time.psychDay: Failed to create date from components: \(comps)")
        }
        return result
    }
}

extension Date {
    var formatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}
