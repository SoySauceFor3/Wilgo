import Foundation
import Testing

@testable import Wilgo

// MARK: - Helpers

/// Builds a Date at the given y/m/d h:m anchored to UTC, so test expectations are
/// deterministic regardless of the machine's local timezone.
private func utcDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = hour
    comps.minute = minute
    comps.second = 0
    comps.timeZone = TimeZone(identifier: "UTC")
    return Calendar(identifier: .gregorian).date(from: comps)!
}

/// Midnight of the given y/m/d in the named timezone, returned as a UTC-based Date.
private func midnight(_ year: Int, _ month: Int, _ day: Int, tz: String) -> Date {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = 0
    comps.minute = 0
    comps.second = 0
    comps.timeZone = TimeZone(identifier: tz)
    return Calendar(identifier: .gregorian).date(from: comps)!
}

// MARK: - CommitmentScheduling.psychDay(for:)
//
// Algorithm recap:
//   1. Shift the input Date back by `dayStartHourOffset` hours.
//   2. Extract (year, month, day) using `timeZoneIdentifier`.
//   3. Return midnight of that calendar day in the same timezone.
//
// All tests below pass an explicit timezone ("UTC") so results are stable on any machine.

@Suite("CommitmentScheduling.psychDay(for:)")
struct CommitmentSchedulingPsychDayTests {

    // MARK: offset 0

    @Suite("offset 0 — any time maps to midnight of the same calendar day")
    struct ZeroOffsetTests {

        @Test("morning → midnight of the same day")
        func morningMapsToday() {
            let now = utcDate(year: 2026, month: 1, day: 1, hour: 9)
            let result = CommitmentScheduling.psychDay(
                for: now, timeZoneIdentifier: "UTC", dayStartHourOffset: 0)
            #expect(result == utcDate(year: 2026, month: 1, day: 1))
        }

        @Test("evening → midnight of the same day")
        func eveningMapsToday() {
            let now = utcDate(year: 2026, month: 1, day: 1, hour: 22)
            let result = CommitmentScheduling.psychDay(
                for: now, timeZoneIdentifier: "UTC", dayStartHourOffset: 0)
            #expect(result == utcDate(year: 2026, month: 1, day: 1))
        }

        @Test("midnight itself → midnight of the same day (no shift)")
        func midnightMapsToday() {
            let now = utcDate(year: 2026, month: 1, day: 1, hour: 0)
            let result = CommitmentScheduling.psychDay(
                for: now, timeZoneIdentifier: "UTC", dayStartHourOffset: 0)
            #expect(result == utcDate(year: 2026, month: 1, day: 1))
        }
    }

    // MARK: offset 14

    @Suite("offset 14 (2 pm day start)")
    struct Offset14Tests {

        // Shift table:
        //   Jan 1 15:00 UTC  -14h → Jan 1 01:00 UTC  → calendar day Jan 1  → midnight Jan 1 UTC  ✓ today
        //   Jan 1 13:00 UTC  -14h → Dec 31 23:00 UTC → calendar day Dec 31 → midnight Dec 31 UTC ✗ yesterday
        //   Jan 1 14:00 UTC  -14h → Jan 1 00:00 UTC  → calendar day Jan 1  → midnight Jan 1 UTC  ✓ today (exact boundary)
        //   Jan 2 01:00 UTC  -14h → Jan 1 11:00 UTC  → calendar day Jan 1  → midnight Jan 1 UTC  ✓ still Jan 1 psych day

        @Test("time after offset (15:00) → psych day is today")
        func afterOffsetIsToday() {
            let now = utcDate(year: 2026, month: 1, day: 1, hour: 15)
            let result = CommitmentScheduling.psychDay(
                for: now, timeZoneIdentifier: "UTC", dayStartHourOffset: 14)
            #expect(result == utcDate(year: 2026, month: 1, day: 1))
        }

        @Test("time before offset (13:00) → psych day is yesterday")
        func beforeOffsetIsYesterday() {
            let now = utcDate(year: 2026, month: 1, day: 1, hour: 13)
            let result = CommitmentScheduling.psychDay(
                for: now, timeZoneIdentifier: "UTC", dayStartHourOffset: 14)
            #expect(result == utcDate(year: 2025, month: 12, day: 31))
        }

        @Test("exactly at offset (14:00) → psych day is today")
        func exactlyAtOffsetIsToday() {
            let now = utcDate(year: 2026, month: 1, day: 1, hour: 14)
            let result = CommitmentScheduling.psychDay(
                for: now, timeZoneIdentifier: "UTC", dayStartHourOffset: 14)
            #expect(result == utcDate(year: 2026, month: 1, day: 1))
        }

        @Test("one minute before offset (13:59) → psych day is yesterday")
        func oneMinuteBeforeOffsetIsYesterday() {
            let now = utcDate(year: 2026, month: 1, day: 1, hour: 13, minute: 59)
            let result = CommitmentScheduling.psychDay(
                for: now, timeZoneIdentifier: "UTC", dayStartHourOffset: 14)
            #expect(result == utcDate(year: 2025, month: 12, day: 31))
        }

        @Test("overnight tail (Jan 2 01:00) → psych day is still Jan 1")
        func overnightTailIsYesterday() {
            let now = utcDate(year: 2026, month: 1, day: 2, hour: 1)
            let result = CommitmentScheduling.psychDay(
                for: now, timeZoneIdentifier: "UTC", dayStartHourOffset: 14)
            #expect(result == utcDate(year: 2026, month: 1, day: 1))
        }

        @Test("Jan 2 14:00 — new psych day starts, result advances to Jan 2")
        func newPsychDayStartsJan2() {
            let now = utcDate(year: 2026, month: 1, day: 2, hour: 14)
            let result = CommitmentScheduling.psychDay(
                for: now, timeZoneIdentifier: "UTC", dayStartHourOffset: 14)
            #expect(result == utcDate(year: 2026, month: 1, day: 2))
        }

        @Test("boundary crossing: 13:59 and 14:00 on the same day land on different psych days")
        func boundaryYieldsAdjacentPsychDays() {
            let before = utcDate(year: 2026, month: 1, day: 1, hour: 13, minute: 59)
            let after = utcDate(year: 2026, month: 1, day: 1, hour: 14, minute: 0)

            let dayBefore = CommitmentScheduling.psychDay(
                for: before, timeZoneIdentifier: "UTC", dayStartHourOffset: 14)
            let dayAfter = CommitmentScheduling.psychDay(
                for: after, timeZoneIdentifier: "UTC", dayStartHourOffset: 14)

            #expect(dayBefore < dayAfter)
            // Exactly one calendar day apart
            let diff = Calendar(identifier: .gregorian).dateComponents(
                [.day], from: dayBefore, to: dayAfter
            ).day!
            #expect(diff == 1)
        }
    }

    // MARK: offset 2

    @Suite("offset 2 (2 am day start)")
    struct Offset2Tests {

        // Shift table:
        //   Jan 1 03:00  -2h → Jan 1 01:00 → day Jan 1 → midnight Jan 1 ✓ today
        //   Jan 1 01:00  -2h → Dec 31 23:00 → day Dec 31 → midnight Dec 31 ✗ yesterday
        //   Jan 1 02:00  -2h → Jan 1 00:00 → day Jan 1 → midnight Jan 1 ✓ today (exact boundary)

        @Test("3 am → psych day is today")
        func threeAmIsToday() {
            let now = utcDate(year: 2026, month: 1, day: 1, hour: 3)
            let result = CommitmentScheduling.psychDay(
                for: now, timeZoneIdentifier: "UTC", dayStartHourOffset: 2)
            #expect(result == utcDate(year: 2026, month: 1, day: 1))
        }

        @Test("1 am → shifted to yesterday, psych day is yesterday")
        func oneAmIsYesterday() {
            let now = utcDate(year: 2026, month: 1, day: 1, hour: 1)
            let result = CommitmentScheduling.psychDay(
                for: now, timeZoneIdentifier: "UTC", dayStartHourOffset: 2)
            #expect(result == utcDate(year: 2025, month: 12, day: 31))
        }

        @Test("exactly 2 am → psych day is today")
        func exactlyAtOffsetIsToday() {
            let now = utcDate(year: 2026, month: 1, day: 1, hour: 2)
            let result = CommitmentScheduling.psychDay(
                for: now, timeZoneIdentifier: "UTC", dayStartHourOffset: 2)
            #expect(result == utcDate(year: 2026, month: 1, day: 1))
        }
    }

    // MARK: timezone sensitivity

    @Suite("timezone parameter is respected")
    struct TimezoneTests {

        // Jan 1 2026 02:00 UTC
        //   = Jan 1 02:00 in UTC        → calendar day Jan 1 → midnight Jan 1 UTC
        //   = Dec 31 2025 21:00 in EST  → calendar day Dec 31 → midnight Dec 31 EST
        // With offset 0 in each timezone, the two calls must return different psych days.

        @Test("UTC vs America/New_York — same instant, different calendar days (offset 0)")
        func utcVsNewYork_offset0() {
            let instant = utcDate(year: 2026, month: 1, day: 1, hour: 2)

            let utcDay = CommitmentScheduling.psychDay(
                for: instant, timeZoneIdentifier: "UTC", dayStartHourOffset: 0)
            let nyDay = CommitmentScheduling.psychDay(
                for: instant, timeZoneIdentifier: "America/New_York", dayStartHourOffset: 0)

            #expect(utcDay == midnight(2026, 1, 1, tz: "UTC"))
            #expect(nyDay == midnight(2025, 12, 31, tz: "America/New_York"))
            #expect(utcDay != nyDay)
        }

        @Test("explicit UTC timezone matches expected midnight UTC")
        func explicitUTCMatchesMidnight() {
            let now = utcDate(year: 2026, month: 6, day: 15, hour: 18)
            let result = CommitmentScheduling.psychDay(
                for: now, timeZoneIdentifier: "UTC", dayStartHourOffset: 0)
            #expect(result == utcDate(year: 2026, month: 6, day: 15))
        }

        @Test("month-end boundary: Dec 31 23:30 UTC with offset 0 stays in December")
        func decemberEndStaysInDecember() {
            let now = utcDate(year: 2025, month: 12, day: 31, hour: 23, minute: 30)
            let result = CommitmentScheduling.psychDay(
                for: now, timeZoneIdentifier: "UTC", dayStartHourOffset: 0)
            #expect(result == utcDate(year: 2025, month: 12, day: 31))
        }

        @Test(
            "year boundary: Jan 1 00:30 UTC with offset 2 shifts into Dec 31, crossing year boundary"
        )
        func yearBoundaryCrossing() {
            // 00:30 UTC Jan 1 2026 -2h → Dec 31 2025 22:30 UTC → psych day Dec 31 2025
            let now = utcDate(year: 2026, month: 1, day: 1, hour: 0, minute: 30)
            let result = CommitmentScheduling.psychDay(
                for: now, timeZoneIdentifier: "UTC", dayStartHourOffset: 2)
            #expect(result == utcDate(year: 2025, month: 12, day: 31))
        }
    }
}
