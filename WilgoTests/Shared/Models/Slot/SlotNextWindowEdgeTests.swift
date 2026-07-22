import Foundation
import Testing
@testable import Wilgo

// MARK: - Helpers

/// A time-of-day reference date. Only hour and minute are meaningful — the same
/// semantics `Slot` uses for its start/end fields.
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

/// A concrete datetime for the given year/month/day (optionally with time).
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

/// `Slot.nextWindowEdge(after:)` — the earliest window edge (an occurrence `start` or `end`) strictly
/// after `instant`. Pure per-slot scheduling: recurrence-aware, ignores snooze/saturation, no
/// container/commitment needed. These tests exercise the primitive directly; the Stage layers
/// (`StageCharacterization.nextTransitionTime`, `nextStageRefreshTime`) are thin fan-outs over it and
/// are tested at their own level only for what they add (the min across commitments, the psychDay fold).
struct SlotNextWindowEdgeTests {
    // Anchor day: Thu Mar 5 2026.
    private let mar5 = date(year: 2026, month: 3, day: 5)

    // MARK: - Upcoming (window not yet started)

    @Test("before an upcoming window → returns that window's start")
    @MainActor func beforeUpcoming_returnsStart() {
        // 8–9 daily slot; instant is 7:00, before today's start.
        let slot = Slot(start: timeOfDay(hour: 8), end: timeOfDay(hour: 9))
        let instant = date(year: 2026, month: 3, day: 5, hour: 7)

        let edge = slot.nextWindowEdge(after: instant)

        #expect(edge == date(year: 2026, month: 3, day: 5, hour: 8))
    }

    @Test("after today's window has ended → returns tomorrow's start")
    @MainActor func afterTodayEnded_returnsNextStart() {
        // 8–9 daily slot; instant is 10:00, after today's end. Next edge is tomorrow's 8:00 start.
        let slot = Slot(start: timeOfDay(hour: 8), end: timeOfDay(hour: 9))
        let instant = date(year: 2026, month: 3, day: 5, hour: 10)

        let edge = slot.nextWindowEdge(after: instant)

        #expect(edge == date(year: 2026, month: 3, day: 6, hour: 8))
    }

    // MARK: - Open (window in progress) — the case that distinguishes this from nextOccurrence

    @Test("while a window is open → returns that window's end")
    @MainActor func openWindow_returnsEnd() {
        // 8–9 daily slot; instant is 8:30, inside the window. `start` is in the past (not a candidate),
        // so the nearest transition is `end` at 9:00.
        let slot = Slot(start: timeOfDay(hour: 8), end: timeOfDay(hour: 9))
        let instant = date(year: 2026, month: 3, day: 5, hour: 8, minute: 30)

        let edge = slot.nextWindowEdge(after: instant)

        #expect(edge == date(year: 2026, month: 3, day: 5, hour: 9))
    }

    // MARK: - Strict `>` boundaries

    @Test("instant exactly at a start → start is not strictly after, returns the same window's end")
    @MainActor func instantAtStart_returnsEnd() {
        // At 8:00 sharp: `start == instant` is not `> instant`, but the window is open (end still ahead),
        // so the edge is `end` at 9:00.
        let slot = Slot(start: timeOfDay(hour: 8), end: timeOfDay(hour: 9))
        let instant = date(year: 2026, month: 3, day: 5, hour: 8)

        let edge = slot.nextWindowEdge(after: instant)

        #expect(edge == date(year: 2026, month: 3, day: 5, hour: 9))
    }

    @Test("instant exactly at an end → end is not strictly after, advances to next window's start")
    @MainActor func instantAtEnd_advances() {
        // At 9:00 sharp: today's `end == instant` is not `> instant` and the window has ended
        // (`end > instant` false), so the walk advances to tomorrow's 8:00 start.
        let slot = Slot(start: timeOfDay(hour: 8), end: timeOfDay(hour: 9))
        let instant = date(year: 2026, month: 3, day: 5, hour: 9)

        let edge = slot.nextWindowEdge(after: instant)

        #expect(edge == date(year: 2026, month: 3, day: 6, hour: 8))
    }

    // MARK: - Recurrence-aware

    @Test("recurrence-aware: a slot that does not fire today skips to its next firing day")
    @MainActor func recurrenceAware_skipsNonFiringDays() {
        // Fri-only 8–9 slot; instant is Thu Mar 5 noon. Today does not fire, so the next edge is
        // Friday Mar 6 at 8:00. (Guards the day-jump: no false "today" edge.)
        let friday = Calendar.current.component(.weekday, from: date(year: 2026, month: 3, day: 6))
        let slot = Slot(
            start: timeOfDay(hour: 8), end: timeOfDay(hour: 9),
            recurrence: .specificWeekdays([friday]))
        let instant = date(year: 2026, month: 3, day: 5, hour: 12)

        let edge = slot.nextWindowEdge(after: instant)

        #expect(edge == date(year: 2026, month: 3, day: 6, hour: 8))
    }

    @Test("empty recurrence set never matches → nil")
    @MainActor func emptyRecurrence_nil() {
        let slot = Slot(
            start: timeOfDay(hour: 8), end: timeOfDay(hour: 9),
            recurrence: .specificWeekdays([]))

        #expect(slot.nextWindowEdge(after: mar5) == nil)
    }

    // MARK: - Three-iteration advance (first match-day's occurrence already ended)

    @Test(
        "first match-day's window already ended → advances to the next match-day (three-iteration path)"
    )
    @MainActor func firstMatchDayEnded_advancesToNextMatchDay() {
        // Wed-only 8–9 slot; instant is Wed Mar 4 at 10:00 — that day *does* fire but its window already
        // ended. The next Wed is Mar 11. Exercises the loop's third iteration across a recurrence gap.
        let wednesday = Calendar.current.component(
            .weekday, from: date(year: 2026, month: 3, day: 4))
        let slot = Slot(
            start: timeOfDay(hour: 8), end: timeOfDay(hour: 9),
            recurrence: .specificWeekdays([wednesday]))
        let instant = date(year: 2026, month: 3, day: 4, hour: 10)

        let edge = slot.nextWindowEdge(after: instant)

        #expect(edge == date(year: 2026, month: 3, day: 11, hour: 8))
    }

    // MARK: - Cross-midnight windows

    @Test(
        "cross-midnight window and the instance is within the window → returns end on the same day as the instance"
    )
    @MainActor func crossMidnight_openPostMidnight_returnsEnd() {
        // 23:00–01:00 daily slot; instant is 00:30 on Mar 5 — inside the tail of the occurrence that
        // started 23:00 on Mar 4. The nearest edge is that occurrence's end at 01:00 on Mar 5.
        let slot = Slot(start: timeOfDay(hour: 23), end: timeOfDay(hour: 1))
        let instant = date(year: 2026, month: 3, day: 5, hour: 0, minute: 30)

        let edge = slot.nextWindowEdge(after: instant)

        #expect(edge == date(year: 2026, month: 3, day: 5, hour: 1))
    }

    @Test("cross-midnight window before it opens → returns that evening's start")
    @MainActor func crossMidnight_beforeOpen_returnsStart() {
        // 23:00–01:00 daily slot; instant is 22:00 on Mar 5, before tonight's 23:00 start.
        let slot = Slot(start: timeOfDay(hour: 23), end: timeOfDay(hour: 1))
        let instant = date(year: 2026, month: 3, day: 5, hour: 22)

        let edge = slot.nextWindowEdge(after: instant)

        #expect(edge == date(year: 2026, month: 3, day: 5, hour: 23))
    }

    // MARK: - Edit reflection (pure Slot level)

    @Test("editing the open window's end moves the returned edge")
    @MainActor func editedEnd_movesEdge() {
        // 8:30 inside an 8–9 window → edge is 9:00. Extend end to 10:00; edge follows to 10:00.
        let slot = Slot(start: timeOfDay(hour: 8), end: timeOfDay(hour: 9))
        let instant = date(year: 2026, month: 3, day: 5, hour: 8, minute: 30)
        #expect(slot.nextWindowEdge(after: instant) == date(year: 2026, month: 3, day: 5, hour: 9))

        slot.end = timeOfDay(hour: 10)
        #expect(slot.nextWindowEdge(after: instant) == date(year: 2026, month: 3, day: 5, hour: 10))
    }
}
