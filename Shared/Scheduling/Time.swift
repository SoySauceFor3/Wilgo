//  Reusable scheduling and "today" time helpers for commitments.
//  Schedule is N× daily only (for now); each occurrence has one slot with its own ideal window.

import Foundation

/// Shared time, date, and calendar utilities.
enum Time {
    static let calendar = Calendar.current

    /// Returns the current date. Override in tests to freeze time.
    /// Production code must never call `Date()` directly — use `Time.now()` instead.
    static var now: () -> Date = { Date() }

    /// Stamps the hour and minute from `timeOfDay` onto the calendar day of `day`.
    /// Precondition:
    /// timeOfDay: Only take hour and minute from this
    /// day:  does not have to be the start of the day
    static func resolve(
        timeOfDay: Date,  // Only take hour and minute from this
        on day: Date = now()  // Does not have to be the start of the day
    ) -> Date {
        let base = calendar.startOfDay(for: day)
        let timeHour = calendar.component(.hour, from: timeOfDay)
        let timeMinute = calendar.component(.minute, from: timeOfDay)
        return calendar.date(
            bySettingHour: timeHour,
            minute: timeMinute,
            second: 0,
            of: base
        ) ?? base
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
