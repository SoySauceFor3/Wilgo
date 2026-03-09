import Foundation
import Testing

@testable import Wilgo

// MARK: - Helpers

/// Builds a concrete Date at the given y/m/d h:m using the same calendar as HabitScheduling.
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

// MARK: - HabitScheduling.today(at:)

@Suite("HabitScheduling.today(at:)")
struct HabitSchedulingTodayTests {

    // MARK: offset 0

    @Suite("offset 0 (default)")
    struct OffsetZeroTests {

        // offset = 0 → the psych day always starts at midnight of the real calendar day,
        // so every time-of-day stamp simply lands on "today".

        @Test("morning time lands on the same calendar day as now")
        func morningLandsToday() {
            let now = date(year: 2026, month: 1, day: 1, hour: 9)
            let result = HabitScheduling.today(
                at: timeOfDay(hour: 8), now: now, dayStartHourOffset: 0)
            #expect(result == date(year: 2026, month: 1, day: 1, hour: 8))
        }

        @Test("midnight (00:00) time lands on the same calendar day as now")
        func midnightLandsToday() {
            let now = date(year: 2026, month: 1, day: 1, hour: 14)
            let result = HabitScheduling.today(
                at: timeOfDay(hour: 0), now: now, dayStartHourOffset: 0)
            #expect(result == date(year: 2026, month: 1, day: 1, hour: 0))
        }

        @Test("late-night time lands on the same calendar day as now")
        func lateNightLandsToday() {
            let now = date(year: 2026, month: 1, day: 1, hour: 23)
            let result = HabitScheduling.today(
                at: timeOfDay(hour: 23, minute: 30), now: now, dayStartHourOffset: 0)
            #expect(result == date(year: 2026, month: 1, day: 1, hour: 23, minute: 30))
        }

        @Test("minute component is preserved")
        func minutePreserved() {
            let now = date(year: 2026, month: 3, day: 5, hour: 10)
            let result = HabitScheduling.today(
                at: timeOfDay(hour: 9, minute: 45), now: now, dayStartHourOffset: 0)
            #expect(result == date(year: 2026, month: 3, day: 5, hour: 9, minute: 45))
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
        func afternoonStaysToday() {
            // now = Jan 1 15:00 → psych day started Jan 1
            let now = date(year: 2026, month: 1, day: 1, hour: 15)
            let result = HabitScheduling.today(
                at: timeOfDay(hour: 20), now: now, dayStartHourOffset: 14)
            #expect(result == date(year: 2026, month: 1, day: 1, hour: 20))
        }

        @Test("2 am slot while now is afternoon pushes to the *next* calendar day")
        func earlyMorningPushesNextDay_afternoonNow() {
            // now = Jan 1 15:00 → psych day started Jan 1 → 2am < 14 → Jan 2 02:00
            let now = date(year: 2026, month: 1, day: 1, hour: 15)
            let result = HabitScheduling.today(
                at: timeOfDay(hour: 2), now: now, dayStartHourOffset: 14)
            #expect(result == date(year: 2026, month: 1, day: 2, hour: 2))
        }

        @Test("exact day-start boundary time (14:00) stays on the psych-day-start date")
        func exactOffsetBoundaryStaysOnStartDate() {
            let now = date(year: 2026, month: 1, day: 1, hour: 14)
            let result = HabitScheduling.today(
                at: timeOfDay(hour: 14), now: now, dayStartHourOffset: 14)
            #expect(result == date(year: 2026, month: 1, day: 1, hour: 14))
        }

        @Test("one minute before day-start boundary (13:59) goes to the next calendar day")
        func oneMinuteBeforeBoundaryNextDay() {
            let now = date(year: 2026, month: 1, day: 1, hour: 14)
            let result = HabitScheduling.today(
                at: timeOfDay(hour: 13, minute: 59), now: now, dayStartHourOffset: 14)
            #expect(result == date(year: 2026, month: 1, day: 2, hour: 13, minute: 59))
        }

        // ── now is in the overnight tail (real clock past midnight, psych day not yet over) ──

        @Test(
            "2 am slot while now is also 2am (overnight) — both resolve to the same psych-day tail")
        func earlyMorningWhileNowIsOvernightToo() {
            // now = Jan 2 02:00 (< 14) → psych day started Jan 1 → 2am → Jan 2 02:00
            let now = date(year: 2026, month: 1, day: 2, hour: 2)
            let result = HabitScheduling.today(
                at: timeOfDay(hour: 2), now: now, dayStartHourOffset: 14)
            #expect(result == date(year: 2026, month: 1, day: 2, hour: 2))
        }

        @Test("evening time while now is in overnight tail resolves to *yesterday* evening")
        func eveningSlotWhileOvernightNow() {
            // now = Jan 2 01:00 (still in Jan 1 psych day) → 20:00 ≥ 14 → Jan 1 20:00
            let now = date(year: 2026, month: 1, day: 2, hour: 1)
            let result = HabitScheduling.today(
                at: timeOfDay(hour: 20), now: now, dayStartHourOffset: 14)
            #expect(result == date(year: 2026, month: 1, day: 1, hour: 20))
        }

        @Test("morning slot (1am) while now is 1am overnight → same night, both Jan 2")
        func morningSlotOvernightNow() {
            // now = Jan 2 01:00 → psych day = Jan 1 → 1am < 14 → Jan 2 01:00
            let now = date(year: 2026, month: 1, day: 2, hour: 1)
            let result = HabitScheduling.today(
                at: timeOfDay(hour: 1), now: now, dayStartHourOffset: 14)
            #expect(result == date(year: 2026, month: 1, day: 2, hour: 1))
        }

        // ── now is exactly at the offset boundary ────────────────────────────────────

        @Test("now is exactly 14:00 — psych day starts today, slots split across the 14h boundary")
        func nowIsExactlyAtOffset() {
            let now = date(year: 2026, month: 1, day: 1, hour: 14)

            let evening = HabitScheduling.today(
                at: timeOfDay(hour: 22), now: now, dayStartHourOffset: 14)
            #expect(evening == date(year: 2026, month: 1, day: 1, hour: 22))

            let morning = HabitScheduling.today(
                at: timeOfDay(hour: 8), now: now, dayStartHourOffset: 14)
            #expect(morning == date(year: 2026, month: 1, day: 2, hour: 8))
        }
    }

    // MARK: offset 2

    @Suite("offset 2 (2 am day start)")
    struct Offset2Tests {

        // Psych day runs from 02:00 → 01:59 next day.
        // Most waking hours are ≥ 2 → stay on psych-day-start date.
        // Only 00:xx and 01:xx go to the next calendar date.

        @Test("1am while now is 10pm — 1am is overnight tail, goes to next calendar day")
        func oneAmIsOvernightTail() {
            // now = Jan 1 22:00 (≥ 2) → psych day started Jan 1 → 1am < 2 → Jan 2 01:00
            let now = date(year: 2026, month: 1, day: 1, hour: 22)
            let result = HabitScheduling.today(
                at: timeOfDay(hour: 1), now: now, dayStartHourOffset: 2)
            #expect(result == date(year: 2026, month: 1, day: 2, hour: 1))
        }

        @Test("3am while now is 10pm — 3am ≥ offset, stays on the same calendar day")
        func threeAmStaysToday() {
            let now = date(year: 2026, month: 1, day: 1, hour: 22)
            let result = HabitScheduling.today(
                at: timeOfDay(hour: 3), now: now, dayStartHourOffset: 2)
            #expect(result == date(year: 2026, month: 1, day: 1, hour: 3))
        }

        @Test("now is 1am (overnight tail) — 10pm slot resolves to *yesterday*")
        func eveningSlotWhileOvernightNow() {
            // now = Jan 2 01:00 (< 2) → psych day started Jan 1 → 22:00 ≥ 2 → Jan 1 22:00
            let now = date(year: 2026, month: 1, day: 2, hour: 1)
            let result = HabitScheduling.today(
                at: timeOfDay(hour: 22), now: now, dayStartHourOffset: 2)
            #expect(result == date(year: 2026, month: 1, day: 1, hour: 22))
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
            let now = date(year: 2026, month: 1, day: 1, hour: 15)

            let evening = HabitScheduling.today(
                at: timeOfDay(hour: 20), now: now, dayStartHourOffset: 14)
            let overnight = HabitScheduling.today(
                at: timeOfDay(hour: 2), now: now, dayStartHourOffset: 14)

            #expect(evening < overnight)
        }

        @Test(
            "evening slot resolves earlier than overnight slot within the same psych day — offset 2"
        )
        func eveningBeforeOvernightOffset2() {
            let now = date(year: 2026, month: 1, day: 1, hour: 15)

            let evening = HabitScheduling.today(
                at: timeOfDay(hour: 20), now: now, dayStartHourOffset: 2)
            let overnight = HabitScheduling.today(
                at: timeOfDay(hour: 1), now: now, dayStartHourOffset: 2)

            #expect(evening < overnight)
        }

        @Test("two evening slots sort correctly")
        func twoEveningSlotsSorted() {
            let now = date(year: 2026, month: 1, day: 1, hour: 15)

            let first = HabitScheduling.today(
                at: timeOfDay(hour: 16), now: now, dayStartHourOffset: 14)
            let second = HabitScheduling.today(
                at: timeOfDay(hour: 21), now: now, dayStartHourOffset: 14)

            #expect(first < second)
        }

        @Test("two overnight slots sort correctly")
        func twoOvernightSlotsSorted() {
            let now = date(year: 2026, month: 1, day: 1, hour: 15)

            let first = HabitScheduling.today(
                at: timeOfDay(hour: 1), now: now, dayStartHourOffset: 14)
            let second = HabitScheduling.today(
                at: timeOfDay(hour: 12), now: now, dayStartHourOffset: 14)

            #expect(first < second)
        }
    }
}
