import Foundation
import Testing

@testable import Wilgo

// MARK: - Helpers

/// Builds a concrete Date at the given y/m/d h:m using the same calendar as Time.
private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = hour
    comps.minute = minute
    comps.second = 0
    return Calendar.current.date(from: comps)!
}

/// Returns a reference Date whose *only* meaningful fields are hour and minute —
/// same as how Slot stores its start/end times.
private func timeOfDay(hour: Int, minute: Int = 0) -> Date {
    date(year: 2000, month: 1, day: 1, hour: hour, minute: minute)
}

@Suite("Time.resolve()")
struct TimeResolveTests {

    // MARK: offset 0

    @Suite("offset 0 (default)")
    struct OffsetZeroTests {

        // offset = 0 → the psych day always starts at midnight of the real calendar day,
        // so every time-of-day stamp simply lands on the same day as psychDay.

        @Test("morning time lands on the same calendar day")
        func morningLandsSameday() {
            let psychDay = date(year: 2026, month: 1, day: 1)
            let result = Time.resolve(
                timeOfDay: timeOfDay(hour: 8), psychDay: psychDay, dayStartHourOffset: 0)
            #expect(result == date(year: 2026, month: 1, day: 1, hour: 8))
        }

        @Test("midnight (00:00) time")
        func midnight() {
            let psychDay = date(year: 2026, month: 1, day: 1)
            let result = Time.resolve(
                timeOfDay: timeOfDay(hour: 0), psychDay: psychDay, dayStartHourOffset: 0)
            #expect(result == date(year: 2026, month: 1, day: 1, hour: 0))
        }

        @Test("late-night time")
        func lateNight() {
            let psychDay = date(year: 2026, month: 1, day: 1)
            let result = Time.resolve(
                timeOfDay: timeOfDay(hour: 23, minute: 30), psychDay: psychDay,
                dayStartHourOffset: 0)
            #expect(result == date(year: 2026, month: 1, day: 1, hour: 23, minute: 30))
        }

        @Test("minute component is preserved")
        func minutePreserved() {
            let psychDay = date(year: 2026, month: 1, day: 1)
            let result = Time.resolve(
                timeOfDay: timeOfDay(hour: 9, minute: 45), psychDay: psychDay, dayStartHourOffset: 0
            )
            #expect(result == date(year: 2026, month: 1, day: 1, hour: 9, minute: 45))
        }
    }

    // MARK: offset 14

    @Suite("offset 14 (2 pm day start)")
    struct Offset14Tests {

        // With offset = 14, the psych day Jan 1 runs from Jan 1 14:00 → Jan 2 13:59.
        // Evening times (≥ 14:00) belong to the psych-day-start calendar date.
        // Overnight/morning times (< 14:00) belong to the *next* calendar date
        // even though they are still psychologically "today".

        // ── now is in the afternoon / evening (past the day-start boundary) ─────────

        @Test("afternoon time (≥ offset) stays on the current calendar day")
        func afternoonStaysSameDay() {
            // now = Jan 1 15:00 → psych day started Jan 1
            let psychDay = date(year: 2026, month: 1, day: 1)
            let result = Time.resolve(
                timeOfDay: timeOfDay(hour: 20), psychDay: psychDay, dayStartHourOffset: 14)
            #expect(result == date(year: 2026, month: 1, day: 1, hour: 20))
        }

        @Test("exact day-start boundary time (14:00) stays on the psych-day-start date")
        func exactOffsetBoundaryStaysSameDay() {
            let psychDay = date(year: 2026, month: 1, day: 1)
            let result = Time.resolve(
                timeOfDay: timeOfDay(hour: 14), psychDay: psychDay, dayStartHourOffset: 14)
            #expect(result == date(year: 2026, month: 1, day: 1, hour: 14))
        }

        @Test("2 am slot while now is afternoon pushes to the *next* calendar day")
        func earlyMorningPushesNextDay() {
            // now = Jan 1 15:00 → psych day started Jan 1 → 2am < 14 → Jan 2 02:00
            let psychDay = date(year: 2026, month: 1, day: 1)
            let result = Time.resolve(
                timeOfDay: timeOfDay(hour: 2), psychDay: psychDay, dayStartHourOffset: 14)
            #expect(result == date(year: 2026, month: 1, day: 2, hour: 2))
        }

        @Test("one minute before day-start boundary (13:59) goes to the next calendar day")
        func oneMinuteBeforeBoundaryPushesNextDay() {
            let psychDay = date(year: 2026, month: 1, day: 1)
            let result = Time.resolve(
                timeOfDay: timeOfDay(hour: 13, minute: 59), psychDay: psychDay,
                dayStartHourOffset: 14)
            #expect(result == date(year: 2026, month: 1, day: 2, hour: 13, minute: 59))
        }
    }

    // MARK: offset 2

    @Suite("offset 2 (2 am day start)")
    struct Offset2Tests {
        @Test("1am, goes to next calendar day")
        func oneAm() {
            let psychDay = date(year: 2026, month: 1, day: 1)
            let result = Time.resolve(
                timeOfDay: timeOfDay(hour: 1), psychDay: psychDay, dayStartHourOffset: 2)
            #expect(result == date(year: 2026, month: 1, day: 2, hour: 1))
        }

        @Test("3am, stays on the same day")
        func threeAmStaysSameDay() {
            let psychDay = date(year: 2026, month: 1, day: 1)
            let result = Time.resolve(
                timeOfDay: timeOfDay(hour: 3), psychDay: psychDay, dayStartHourOffset: 2)
            #expect(result == date(year: 2026, month: 1, day: 1, hour: 3))
        }

        @Test("10pm")
        func tenPm() {
            let psychDay = date(year: 2026, month: 1, day: 1)
            let result = Time.resolve(
                timeOfDay: timeOfDay(hour: 22), psychDay: psychDay, dayStartHourOffset: 2)
            #expect(result == date(year: 2026, month: 1, day: 1, hour: 22))
        }
    }

    @Suite("psychDay parameter is not the sart of the day")
    struct DirtyPsychDayTests {
        @Test("psychDay has hour set as 11pm")
        func psychDay11pm() {
            let psychDay = date(year: 2026, month: 1, day: 1, hour: 23)
            let result = Time.resolve(
                timeOfDay: timeOfDay(hour: 23), psychDay: psychDay, dayStartHourOffset: 0)
            #expect(result == date(year: 2026, month: 1, day: 1, hour: 23))
        }
    }

    // MARK: ordering invariant

    @Suite("slot ordering within a psych day")
    struct OrderingTests {

        // A psych day's slots must sort chronologically after resolution:
        //   evening slot (e.g. 20:00) < overnight slot (e.g. 02:00 next real day)

        @Test(
            "evening slot resolves earlier than overnight slot within the same psych day — offset 14"
        )
        func eveningBeforeOvernightOffset14() {
            let psychDay = date(year: 2026, month: 1, day: 1)

            let evening = Time.resolve(
                timeOfDay: timeOfDay(hour: 20), psychDay: psychDay, dayStartHourOffset: 14)
            let overnight = Time.resolve(
                timeOfDay: timeOfDay(hour: 2), psychDay: psychDay, dayStartHourOffset: 14)

            #expect(evening < overnight)
        }

        @Test(
            "evening slot resolves earlier than overnight slot within the same psych day — offset 2"
        )
        func eveningBeforeOvernightOffset2() {
            let psychDay = date(year: 2026, month: 1, day: 1)

            let evening = Time.resolve(
                timeOfDay: timeOfDay(hour: 20), psychDay: psychDay, dayStartHourOffset: 2)
            let overnight = Time.resolve(
                timeOfDay: timeOfDay(hour: 1), psychDay: psychDay, dayStartHourOffset: 2)

            #expect(evening < overnight)
        }

        @Test("two evening slots sort correctly")
        func twoEveningSlotsSorted() {
            let psychDay = date(year: 2026, month: 1, day: 1)

            let first = Time.resolve(
                timeOfDay: timeOfDay(hour: 16), psychDay: psychDay, dayStartHourOffset: 14)
            let second = Time.resolve(
                timeOfDay: timeOfDay(hour: 21), psychDay: psychDay, dayStartHourOffset: 14)

            #expect(first < second)
        }

        @Test("two overnight slots sort correctly")
        func twoOvernightSlotsSorted() {
            let psychDay = date(year: 2026, month: 1, day: 1)

            let first = Time.resolve(
                timeOfDay: timeOfDay(hour: 1), psychDay: psychDay, dayStartHourOffset: 14)
            let second = Time.resolve(
                timeOfDay: timeOfDay(hour: 12), psychDay: psychDay, dayStartHourOffset: 14)

            #expect(first < second)
        }
    }
}
