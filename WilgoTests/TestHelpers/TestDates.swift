import Foundation

// MARK: - Shared date/time test helpers

/// Builds a concrete `Date` at the given year/month/day and optional time, using
/// `Calendar.current` (the same calendar the production date math uses).
///
/// Named `testDate` rather than `date` to avoid confusion with `Foundation.Date`
/// and to make intent obvious at call sites.
func testDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = hour
    comps.minute = minute
    comps.second = 0
    return Calendar.current.date(from: comps)!
}

/// Returns a reference `Date` whose *only* meaningful fields are hour and minute —
/// the y2000 "time-only" convention that `Slot` uses to store its start/end times.
func timeOfDay(hour: Int, minute: Int = 0) -> Date {
    testDate(year: 2000, month: 1, day: 1, hour: hour, minute: minute)
}
