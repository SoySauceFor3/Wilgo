import Foundation
import Testing
@testable import Wilgo

// MARK: - Helpers
/// `Slot.occurrences(from:until:softFrom:softUntil:)` — pure per-slot enumeration over a datetime
/// window. No container/commitment needed: the method is deliberately independent of check-ins.
extension SlotSuite {
struct SlotOccurrencesTests {
    // MARK: - Basic windowing

    @Test("occurrence fully inside the window is returned")
    @MainActor func fullyInside_returned() {
        // 9–11 daily slot; window 7–12 on Mar 5.
        let slot = Slot(start: timeOfDay(hour: 9), end: timeOfDay(hour: 11))
        let from = testDate(year: 2026, month: 3, day: 5, hour: 7)
        let until = testDate(year: 2026, month: 3, day: 5, hour: 12)

        let occs = slot.occurrences(from: from, until: until)

        #expect(occs.map(\.start) == [testDate(year: 2026, month: 3, day: 5, hour: 9)])
    }

    @Test("occurrence fully outside the window is never built")
    @MainActor func fullyOutside_excluded() {
        // 9–11 slot; window 6–8 ends before the slot starts.
        let slot = Slot(start: timeOfDay(hour: 9), end: timeOfDay(hour: 11))
        let from = testDate(year: 2026, month: 3, day: 5, hour: 6)
        let until = testDate(year: 2026, month: 3, day: 5, hour: 8)

        #expect(slot.occurrences(from: from, until: until).isEmpty)
    }

    @Test("daily slot across several days yields one occurrence per day in window")
    @MainActor func multiDay_oneOccurrencePerDay() {
        let slot = Slot(start: timeOfDay(hour: 9), end: timeOfDay(hour: 11))
        let from = testDate(year: 2026, month: 3, day: 5, hour: 7)
        let until = testDate(year: 2026, month: 3, day: 8)  // exclusive: Mar 5, 6, 7

        let starts = slot.occurrences(from: from, until: until).map(\.start)

        #expect(starts.count == 3)
        #expect(starts.contains(testDate(year: 2026, month: 3, day: 5, hour: 9)))
        #expect(starts.contains(testDate(year: 2026, month: 3, day: 6, hour: 9)))
        #expect(starts.contains(testDate(year: 2026, month: 3, day: 7, hour: 9)))
    }

    @Test("occurrences are returned in day order")
    @MainActor func multiDay_dayOrder() {
        let slot = Slot(start: timeOfDay(hour: 9), end: timeOfDay(hour: 11))
        let from = testDate(year: 2026, month: 3, day: 5, hour: 7)
        let until = testDate(year: 2026, month: 3, day: 8)

        let starts = slot.occurrences(from: from, until: until).map(\.start)

        #expect(starts == starts.sorted())
    }

    // MARK: - softFrom (the `from` edge)

    @Test("occurrence straddling `from`: kept by default, dropped when softFrom is false")
    @MainActor func firstHalf_gatedBySoftFrom() {
        // `from` at 10 lands inside the 9–11 window → the occurrence starts before `from`.
        let slot = Slot(start: timeOfDay(hour: 9), end: timeOfDay(hour: 11))
        let from = testDate(year: 2026, month: 3, day: 5, hour: 10)
        let until = testDate(year: 2026, month: 3, day: 5, hour: 12)

        #expect(
            slot.occurrences(from: from, until: until).map(\.start)
                == [testDate(year: 2026, month: 3, day: 5, hour: 9)])
        #expect(slot.occurrences(from: from, until: until, softFrom: false).isEmpty)
    }

    @Test(
        "cross-midnight occurrence anchored on the prior day reaches into the window, when softFrom is true"
    )
    @MainActor func crossMidnight_priorDayCarryOver() {
        // 23–01 cross-midnight daily slot; window opens at 00:30 on Mar 5 — *inside* the tail of the
        // occurrence that started 23:00 the previous day (Mar 4), which ends at 01:00. (Opening at
        // exactly 01:00 would put `from == occ.end`, and the half-open overlap test `end > from`
        // would correctly exclude it — a distinct boundary case, not what we're testing here.)
        let slot = Slot(start: timeOfDay(hour: 23), end: timeOfDay(hour: 1))
        let from = testDate(year: 2026, month: 3, day: 5, hour: 0, minute: 30)
        let until = testDate(year: 2026, month: 3, day: 5, hour: 12)
        let priorStart = testDate(year: 2026, month: 3, day: 4, hour: 23)

        // The prior-day occurrence is a first-half straddler (starts before `from`).
        #expect(slot.occurrences(from: from, until: until).map(\.start).contains(priorStart))
        // softFrom: false drops it, since it crosses the `from` edge.
        #expect(
            !slot.occurrences(from: from, until: until, softFrom: false).map(\.start).contains(
                priorStart))
    }

    // MARK: - softUntil (the `until` edge)

    @Test("occurrence straddling `until`: kept by default, dropped when softUntil is false")
    @MainActor func secondHalf_gatedBySoftUntil() {
        // `until` at 10 lands inside the 9–11 window → the occurrence ends past `until`.
        let slot = Slot(start: timeOfDay(hour: 9), end: timeOfDay(hour: 11))
        let from = testDate(year: 2026, month: 3, day: 5, hour: 7)
        let until = testDate(year: 2026, month: 3, day: 5, hour: 10)

        #expect(
            slot.occurrences(from: from, until: until).map(\.start)
                == [testDate(year: 2026, month: 3, day: 5, hour: 9)])
        #expect(slot.occurrences(from: from, until: until, softUntil: false).isEmpty)
    }

    @Test("occurrence ending exactly at `until` is fully inside — softUntil does not drop it")
    @MainActor func endsFlushWithUntil_notGatedBySoftUntil() {
        // 9–11 slot; window ends exactly at 11. `end == until`, and `end` is exclusive, so the
        // occurrence occupies no time at or past `until` → fully inside, never a straddler.
        let slot = Slot(start: timeOfDay(hour: 9), end: timeOfDay(hour: 11))
        let from = testDate(year: 2026, month: 3, day: 5, hour: 7)
        let until = testDate(year: 2026, month: 3, day: 5, hour: 11)

        #expect(
            slot.occurrences(from: from, until: until, softUntil: false).map(\.start)
                == [testDate(year: 2026, month: 3, day: 5, hour: 9)])
    }

    // MARK: - Fully-covering occurrence (crosses both edges)

    @Test("occurrence covering the whole window needs both edges soft")
    @MainActor func fullyCovering_needsBothSoft() {
        // A 9–17 occurrence engulfs the narrow 10–12 window: starts before `from`, ends after `until`.
        let slot = Slot(start: timeOfDay(hour: 9), end: timeOfDay(hour: 17))
        let from = testDate(year: 2026, month: 3, day: 5, hour: 10)
        let until = testDate(year: 2026, month: 3, day: 5, hour: 12)
        let expected = testDate(year: 2026, month: 3, day: 5, hour: 9)

        // Default (both soft): kept.
        #expect(slot.occurrences(from: from, until: until).map(\.start) == [expected])
        // Either edge hard drops it, since it crosses that edge.
        #expect(slot.occurrences(from: from, until: until, softFrom: false).isEmpty)
        #expect(slot.occurrences(from: from, until: until, softUntil: false).isEmpty)
    }

    // MARK: - Recurrence gating

    @Test("weekday recurrence only enumerates matching days")
    @MainActor func weekdayRecurrence_onlyMatchingDays() {
        // Saturday-only (weekday 7). 2026-03-07 is Saturday; 03-06 (Fri) and 03-08 (Sun) are not.
        let slot = Slot(
            start: timeOfDay(hour: 9), end: timeOfDay(hour: 11),
            recurrence: .specificWeekdays([7]))
        let from = testDate(year: 2026, month: 3, day: 6)
        let until = testDate(year: 2026, month: 3, day: 9)

        let starts = slot.occurrences(from: from, until: until).map(\.start)

        #expect(starts == [testDate(year: 2026, month: 3, day: 7, hour: 9)])
    }

    @Test("recurrence that never matches in the window yields nothing")
    @MainActor func noMatchingDay_empty() {
        // Month-day 25 only; the Mar 5–8 window contains no 25th.
        let slot = Slot(
            start: timeOfDay(hour: 9), end: timeOfDay(hour: 11),
            recurrence: .specificMonthDays([25]))
        let from = testDate(year: 2026, month: 3, day: 5)
        let until = testDate(year: 2026, month: 3, day: 8)

        #expect(slot.occurrences(from: from, until: until).isEmpty)
    }
}
}

/// `SlotOccurrence: Comparable` — chronological `<` by `(start, end)`, distinct from identity `==`.
extension SlotSuite {
struct SlotOccurrenceComparableTests {
    private let day = testDate(year: 2026, month: 3, day: 5)

    @Test("earlier window start sorts first")
    @MainActor func earlierStart_ordersFirst() throws {
        let morning = Slot(start: timeOfDay(hour: 9), end: timeOfDay(hour: 11))
        let evening = Slot(start: timeOfDay(hour: 18), end: timeOfDay(hour: 20))
        let m = try #require(morning.occurrence(on: day))
        let e = try #require(evening.occurrence(on: day))

        #expect(m < e)
        #expect([e, m].sorted() == [m, e])
    }

    @Test("equal start: shorter window (earlier end) sorts first")
    @MainActor func equalStart_shorterEndsFirst() throws {
        let short = Slot(start: timeOfDay(hour: 9), end: timeOfDay(hour: 10))
        let long = Slot(start: timeOfDay(hour: 9), end: timeOfDay(hour: 12))
        let s = try #require(short.occurrence(on: day))
        let l = try #require(long.occurrence(on: day))

        #expect(s.start == l.start)  // same start → tie-break on end
        #expect(s < l)
    }

    @Test("identity `==` is same-firing, independent of chronological `<`")
    @MainActor func identityEquality_distinctFromOrdering() throws {
        let slot = Slot(start: timeOfDay(hour: 9), end: timeOfDay(hour: 11))
        // Same slot + same day → same firing → equal, and neither is `<` the other.
        let a = try #require(slot.occurrence(on: day))
        let b = try #require(slot.occurrence(on: day))
        #expect(a == b)
        #expect(!(a < b) && !(b < a))

        // Two *different* slots sharing an identical window: they tie under `<` (neither ordered)
        // yet are NOT `==` — ordering and identity answer different questions.
        let twin = Slot(start: timeOfDay(hour: 9), end: timeOfDay(hour: 11))
        let t = try #require(twin.occurrence(on: day))
        #expect(a.start == t.start && a.end == t.end)  // identical windows
        #expect(!(a < t) && !(t < a))  // tie under <
        #expect(a != t)  // but distinct firings
    }
}
}
