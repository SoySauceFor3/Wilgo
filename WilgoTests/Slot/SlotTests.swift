import Foundation
import Testing

@testable import Wilgo

// MARK: - Helpers

/// A time-of-day reference date. Only hour and minute are meaningful — the same
/// semantics Slot uses for its start/end fields.
private func timeOfDay(hour: Int, minute: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = 2000
    comps.month = 1
    comps.day = 1
    comps.hour = hour
    comps.minute = minute
    comps.second = 0
    return Calendar.current.date(from: comps)!
}

/// Returns a Date for the given year/month/day (optionally with time).
private func date(
    year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0
) -> Date {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = hour
    comps.minute = minute
    comps.second = 0
    return Calendar.current.date(from: comps)!
}

@Suite("Slot tests")
struct SlotTests {

    // MARK: - SlotRecurrence.matches

    @Suite("SlotRecurrence — matches")
    struct SlotRecurrenceMatchesTests {
        private let calendar = Calendar.current

        @Test("everyDay matches any date")
        func everyDay_matchesAny() {
            let rule = SlotRecurrence.everyDay
            #expect(rule.matches(date: date(year: 2026, month: 4, day: 25), calendar: calendar))
            #expect(rule.matches(date: date(year: 2026, month: 1, day: 1), calendar: calendar))
        }

        @Test("specificWeekdays matches correct weekday")
        func specificWeekdays_matchesCorrect() {
            // 2026-04-25 is a Saturday (weekday 7)
            let rule = SlotRecurrence.specificWeekdays([7])
            #expect(rule.matches(date: date(year: 2026, month: 4, day: 25), calendar: calendar))
        }

        @Test("specificWeekdays rejects wrong weekday")
        func specificWeekdays_rejectsWrong() {
            // 2026-04-25 is Saturday (7), rule is Monday only (2)
            let rule = SlotRecurrence.specificWeekdays([2])
            #expect(!rule.matches(date: date(year: 2026, month: 4, day: 25), calendar: calendar))
        }

        @Test("specificMonthDays matches correct day")
        func specificMonthDays_matchesCorrect() {
            let rule = SlotRecurrence.specificMonthDays([25])
            #expect(rule.matches(date: date(year: 2026, month: 4, day: 25), calendar: calendar))
        }

        @Test("specificMonthDays rejects wrong day")
        func specificMonthDays_rejectsWrong() {
            let rule = SlotRecurrence.specificMonthDays([1, 15])
            #expect(!rule.matches(date: date(year: 2026, month: 4, day: 25), calendar: calendar))
        }

        @Test("matches ignores time-of-day component")
        func matches_ignoresTimeOfDay() {
            // Saturday at 14:30 should still match weekday 7
            let rule = SlotRecurrence.specificWeekdays([7])
            #expect(
                rule.matches(
                    date: date(year: 2026, month: 4, day: 25, hour: 14, minute: 30),
                    calendar: calendar
                ))
        }
    }

    // MARK: - Slot.isScheduled

    @Suite("Slot — isScheduled")
    struct SlotIsScheduledTests {

        private let calendar = Calendar.current

        // MARK: everyDay recurrence

        @Suite("everyDay recurrence")
        struct EveryDayTests {

            @Test("same-day window includes boundaries and interior")
            @MainActor func sameDay_includesBoundariesAndInterior() throws {
                let slot = Slot(
                    start: timeOfDay(hour: 9, minute: 0),
                    end: timeOfDay(hour: 11, minute: 0)
                )

                #expect(slot.isScheduled(on: timeOfDay(hour: 9, minute: 0)))
                #expect(slot.isScheduled(on: timeOfDay(hour: 10, minute: 0)))
                #expect(slot.isScheduled(on: timeOfDay(hour: 11, minute: 0)))
            }

            @Test("same-day window excludes outside times")
            @MainActor func sameDay_excludesOutside() throws {
                let slot = Slot(
                    start: timeOfDay(hour: 9, minute: 0),
                    end: timeOfDay(hour: 11, minute: 0)
                )

                #expect(!slot.isScheduled(on: timeOfDay(hour: 8, minute: 59)))
                #expect(!slot.isScheduled(on: timeOfDay(hour: 11, minute: 1)))
            }

            @Test("cross-midnight window includes boundaries and interior")
            @MainActor func crossMidnight_includesBoundariesAndInterior() throws {
                let slot = Slot(
                    start: timeOfDay(hour: 23, minute: 0),
                    end: timeOfDay(hour: 1, minute: 0)
                )

                #expect(slot.isScheduled(on: timeOfDay(hour: 23, minute: 0)))
                #expect(slot.isScheduled(on: timeOfDay(hour: 0, minute: 0)))
                #expect(slot.isScheduled(on: timeOfDay(hour: 1, minute: 0)))
            }

            @Test("cross-midnight window excludes outside times")
            @MainActor func crossMidnight_excludesOutside() throws {
                let slot = Slot(
                    start: timeOfDay(hour: 23, minute: 0),
                    end: timeOfDay(hour: 1, minute: 0)
                )

                #expect(!slot.isScheduled(on: timeOfDay(hour: 22, minute: 59)))
                #expect(!slot.isScheduled(on: timeOfDay(hour: 1, minute: 1)))
            }
        }

        // MARK: specificWeekdays recurrence

        @Suite("specificWeekdays recurrence")
        struct SpecificWeekdaysTests {

            private let calendar = Calendar.current

            // 2026-04-25 is a Saturday (weekday 7).
            // 2026-04-26 is a Sunday (weekday 1).

            @Test("same-day window — matching weekday is scheduled")
            @MainActor func sameDay_matchingWeekday_isScheduled() {
                let slot = Slot(
                    start: timeOfDay(hour: 9, minute: 0),
                    end: timeOfDay(hour: 11, minute: 0),
                    recurrence: .specificWeekdays([7])  // Saturday
                )
                // 09:30 on Saturday 2026-04-25 — inside window, correct weekday.
                #expect(
                    slot.isScheduled(
                        on: date(year: 2026, month: 4, day: 25, hour: 9, minute: 30),
                        calendar: calendar))
            }

            @Test("same-day window — wrong weekday is not scheduled")
            @MainActor func sameDay_wrongWeekday_notScheduled() {
                let slot = Slot(
                    start: timeOfDay(hour: 9, minute: 0),
                    end: timeOfDay(hour: 11, minute: 0),
                    recurrence: .specificWeekdays([7])  // Saturday only
                )
                // 09:30 on Sunday 2026-04-26 — inside window, wrong weekday.
                #expect(
                    !slot.isScheduled(
                        on: date(year: 2026, month: 4, day: 26, hour: 9, minute: 30),
                        calendar: calendar))
            }

            @Test("cross-midnight window — pre-midnight portion on matching weekday is scheduled")
            @MainActor func crossMidnight_preMidnight_matchingWeekday_isScheduled() {
                let slot = Slot(
                    start: timeOfDay(hour: 23, minute: 0),
                    end: timeOfDay(hour: 1, minute: 0),
                    recurrence: .specificWeekdays([7])  // Saturday
                )
                // 23:30 on Saturday 2026-04-25 — pre-midnight, anchor = Saturday.
                #expect(
                    slot.isScheduled(
                        on: date(year: 2026, month: 4, day: 25, hour: 23, minute: 30),
                        calendar: calendar))
            }

            @Test(
                "cross-midnight window — post-midnight portion anchors to previous day (Saturday), is scheduled"
            )
            @MainActor func crossMidnight_postMidnight_anchorsToSaturday_isScheduled() {
                let slot = Slot(
                    start: timeOfDay(hour: 23, minute: 0),
                    end: timeOfDay(hour: 1, minute: 0),
                    recurrence: .specificWeekdays([7])  // Saturday
                )
                // 00:30 on Sunday 2026-04-26 — post-midnight, anchor = Saturday 2026-04-25.
                #expect(
                    slot.isScheduled(
                        on: date(year: 2026, month: 4, day: 26, hour: 0, minute: 30),
                        calendar: calendar))
            }

            @Test("cross-midnight window — pre-midnight portion on wrong weekday is not scheduled")
            @MainActor func crossMidnight_preMidnight_wrongWeekday_notScheduled() {
                let slot = Slot(
                    start: timeOfDay(hour: 23, minute: 0),
                    end: timeOfDay(hour: 1, minute: 0),
                    recurrence: .specificWeekdays([7])  // Saturday only
                )
                // 23:30 on Sunday 2026-04-26 — pre-midnight, anchor = Sunday, not Saturday.
                #expect(
                    !slot.isScheduled(
                        on: date(year: 2026, month: 4, day: 26, hour: 23, minute: 30),
                        calendar: calendar))
            }
        }

        // MARK: specificMonthDays recurrence

        @Suite("specificMonthDays recurrence")
        struct SpecificMonthDaysTests {

            private let calendar = Calendar.current

            @Test("same-day window — matching month day is scheduled")
            @MainActor func sameDay_matchingMonthDay_isScheduled() {
                let slot = Slot(
                    start: timeOfDay(hour: 9, minute: 0),
                    end: timeOfDay(hour: 11, minute: 0),
                    recurrence: .specificMonthDays([25])
                )
                // 09:30 on 2026-04-25 — inside window, day 25.
                #expect(
                    slot.isScheduled(
                        on: date(year: 2026, month: 4, day: 25, hour: 9, minute: 30),
                        calendar: calendar))
            }

            @Test("same-day window — wrong month day is not scheduled")
            @MainActor func sameDay_wrongMonthDay_notScheduled() {
                let slot = Slot(
                    start: timeOfDay(hour: 9, minute: 0),
                    end: timeOfDay(hour: 11, minute: 0),
                    recurrence: .specificMonthDays([25])
                )
                // 09:30 on 2026-04-26 — inside window, day 26 ≠ 25.
                #expect(
                    !slot.isScheduled(
                        on: date(year: 2026, month: 4, day: 26, hour: 9, minute: 30),
                        calendar: calendar))
            }

            @Test(
                "cross-midnight window — post-midnight portion anchors to day 25 (previous day), is scheduled"
            )
            @MainActor func crossMidnight_postMidnight_anchorsToDay25_isScheduled() {
                let slot = Slot(
                    start: timeOfDay(hour: 23, minute: 0),
                    end: timeOfDay(hour: 1, minute: 0),
                    recurrence: .specificMonthDays([25])
                )
                // 00:30 on 2026-04-26 — post-midnight, anchor = 2026-04-25 (day 25).
                #expect(
                    slot.isScheduled(
                        on: date(year: 2026, month: 4, day: 26, hour: 0, minute: 30),
                        calendar: calendar))
            }

            @Test(
                "cross-midnight window — post-midnight portion on wrong anchor day is not scheduled"
            )
            @MainActor func crossMidnight_postMidnight_wrongAnchorDay_notScheduled() {
                let slot = Slot(
                    start: timeOfDay(hour: 23, minute: 0),
                    end: timeOfDay(hour: 1, minute: 0),
                    recurrence: .specificMonthDays([25])
                )
                // 00:30 on 2026-04-27 — post-midnight, anchor = 2026-04-26 (day 26 ≠ 25).
                #expect(
                    !slot.isScheduled(
                        on: date(year: 2026, month: 4, day: 27, hour: 0, minute: 30),
                        calendar: calendar))
            }
        }

    }

    // MARK: - Slot.isScheduled (whole-day slots)

    @Suite("Slot — isScheduled (whole-day)")
    struct SlotWholeDayIsScheduledTests {

        private let calendar = Calendar.current

        // Whole-day sentinel: start == end (same minutes-since-midnight).
        // 2026-04-25 is a Saturday (weekday 7).
        // 2026-04-26 is a Sunday (weekday 1).
        // 2026-04-27 is a Monday (weekday 2).

        private func wholeDaySlot(recurrence: SlotRecurrence = .everyDay) -> Slot {
            Slot(start: timeOfDay(hour: 0), end: timeOfDay(hour: 0), recurrence: recurrence)
        }

        // MARK: everyDay

        @Test("everyDay whole-day sloty")
        @MainActor func everyDay_scheduledAtAnyTime() {
            let slot = wholeDaySlot()
            #expect(
                slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 25, hour: 0, minute: 0), calendar: calendar)
            )
            #expect(
                slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 25, hour: 12, minute: 0), calendar: calendar
                ))
            #expect(
                slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 25, hour: 23, minute: 59),
                    calendar: calendar))
        }

        // MARK: specificWeekdays

        @Test("specificWeekdays whole-day slot")
        @MainActor func specificWeekdays_matchingDay_scheduledAllDay() {
            let slot = wholeDaySlot(recurrence: .specificWeekdays([7]))  // Saturday
            #expect(
                slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 25, hour: 0, minute: 0), calendar: calendar)
            )
            #expect(
                slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 25, hour: 14, minute: 0), calendar: calendar
                ))
            #expect(
                slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 25, hour: 23, minute: 59),
                    calendar: calendar))
            #expect(
                !slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 26, hour: 9, minute: 0), calendar: calendar)
            )  // Sunday
            #expect(
                !slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 27, hour: 9, minute: 0), calendar: calendar)
            )  // Monday
        }

        // A 5am–5am slot: whole-day sentinel with a non-midnight sentinel time.
        // Pre-5am times (e.g. 4am) are in the post-midnight portion of the cross-midnight
        // window, so anchorDate returns the *previous* calendar day.
        // 2026-04-27 is a Monday (weekday 2). 2026-04-26 is a Sunday (weekday 1).

        @Test("5am–5am slot: 4am on Monday anchors to Sunday — not scheduled for Monday-only rule")
        @MainActor func fiveAM_sentinel_preSentinelTime_anchorsToYesterday_weekdays() {
            // Monday-only slot using 5am sentinel.
            let ref = timeOfDay(hour: 5)
            let slot = Slot(start: ref, end: ref, recurrence: .specificWeekdays([2]))  // Monday
            // 4am on Monday 2026-04-27: post-midnight portion → anchor = Sunday 2026-04-26 (weekday 1 ≠ 2).
            #expect(
                !slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 27, hour: 4, minute: 0), calendar: calendar)
            )
        }

        @Test("5am–5am slot: 6am on Monday anchors to Monday — scheduled for Monday-only rule")
        @MainActor func fiveAM_sentinel_postSentinelTime_anchorsToToday_weekdays() {
            let ref = timeOfDay(hour: 5)
            let slot = Slot(start: ref, end: ref, recurrence: .specificWeekdays([2]))  // Monday
            // 6am on Monday 2026-04-27: pre-midnight portion (6am >= 5am) → anchor = Monday 2026-04-27 (weekday 2 ✓).
            #expect(
                slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 27, hour: 6, minute: 0), calendar: calendar)
            )
        }

        @Test(
            "5am–5am slot: 4am on day-1 anchors to previous day — not scheduled for day-1-only rule"
        )
        @MainActor func fiveAM_sentinel_preSentinelTime_anchorsToYesterday_monthDays() {
            let ref = timeOfDay(hour: 5)
            let slot = Slot(start: ref, end: ref, recurrence: .specificMonthDays([1]))  // 1st of month
            // 4am on 2026-04-01: post-midnight portion → anchor = 2026-03-31 (day 31 ≠ 1).
            #expect(
                !slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 1, hour: 4, minute: 0), calendar: calendar))
        }

        @Test("5am–5am slot: 6am on day-1 anchors to day-1 — scheduled for day-1-only rule")
        @MainActor func fiveAM_sentinel_postSentinelTime_anchorsToToday_monthDays() {
            let ref = timeOfDay(hour: 5)
            let slot = Slot(start: ref, end: ref, recurrence: .specificMonthDays([1]))  // 1st of month
            // 6am on 2026-04-01: pre-midnight portion (6am >= 5am) → anchor = 2026-04-01 (day 1 ✓).
            #expect(
                slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 1, hour: 6, minute: 0), calendar: calendar))
        }

        @Test("specificWeekdays whole-day slot with multiple weekdays")
        @MainActor func specificWeekdays_multipleDays() {
            let slot = wholeDaySlot(recurrence: .specificWeekdays([7, 1]))  // Saturday + Sunday
            #expect(
                slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 25, hour: 10, minute: 0), calendar: calendar
                ))  // Saturday
            #expect(
                slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 26, hour: 10, minute: 0), calendar: calendar
                ))  // Sunday
            #expect(
                !slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 27, hour: 10, minute: 0), calendar: calendar
                ))  // Monday
        }

        // MARK: specificMonthDays

        @Test("specificMonthDays whole-day slot")
        @MainActor func specificMonthDays_matchingDay_scheduledAllDay() {
            let slot = wholeDaySlot(recurrence: .specificMonthDays([25]))
            #expect(
                slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 25, hour: 0, minute: 0), calendar: calendar)
            )
            #expect(
                slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 25, hour: 12, minute: 0), calendar: calendar
                ))
            #expect(
                slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 25, hour: 23, minute: 59),
                    calendar: calendar))
            #expect(
                !slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 24, hour: 9, minute: 0), calendar: calendar)
            )
            #expect(
                !slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 26, hour: 9, minute: 0), calendar: calendar)
            )
        }

        @Test("specificMonthDays whole-day slot with multiple month days")
        @MainActor func specificMonthDays_multipleDays() {
            let slot = wholeDaySlot(recurrence: .specificMonthDays([1, 25]))
            #expect(
                slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 1, hour: 10, minute: 0), calendar: calendar)
            )
            #expect(
                slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 25, hour: 10, minute: 0), calendar: calendar
                ))
            #expect(
                !slot.isScheduled(
                    on: date(year: 2026, month: 4, day: 15, hour: 10, minute: 0), calendar: calendar
                ))
        }
    }

    @Suite("Slot — remainingFraction")
    struct SlotRemainingFractionTests {
        @Test("remainingFraction — same-day window fractions")
        @MainActor func remainingFraction_sameDay() throws {
            let slot = Slot(
                start: timeOfDay(hour: 10, minute: 0),
                end: timeOfDay(hour: 11, minute: 0),
                recurrence: .everyDay
            )

            // Full window remaining at start.
            #expect(slot.remainingFraction(at: timeOfDay(hour: 10, minute: 0)) == 1.0)
            // Half window remaining at halfway point.
            #expect(slot.remainingFraction(at: timeOfDay(hour: 10, minute: 30)) == 0.5)
            // No time remaining at end.
            #expect(slot.remainingFraction(at: timeOfDay(hour: 11, minute: 0)) == 0.0)
        }

        @Test("remainingFraction — cross-midnight window fractions")
        @MainActor func remainingFraction_crossMidnight() throws {
            let slot = Slot(
                start: timeOfDay(hour: 23, minute: 0),
                end: timeOfDay(hour: 1, minute: 0)
            )

            // Window length is 2 hours (120 minutes): 23:00–01:00.
            #expect(slot.remainingFraction(at: timeOfDay(hour: 23, minute: 0)) == 1.0)
            // One hour (60 minutes) remaining at midnight.
            #expect(slot.remainingFraction(at: timeOfDay(hour: 0, minute: 0)) == 0.5)
            // No time remaining at end.
            #expect(slot.remainingFraction(at: timeOfDay(hour: 1, minute: 0)) == 0.0)
        }
    }
}
