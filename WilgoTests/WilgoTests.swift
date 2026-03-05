import Testing
import SwiftData
import Foundation
@testable import Wilgo

// MARK: - Helpers

/// Builds a Date at the given y/m/d h:m in the current calendar (matches HabitScheduling.calendar).
private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = year; comps.month = month; comps.day = day
    comps.hour = hour; comps.minute = minute; comps.second = 0
    return Calendar.current.date(from: comps)!
}

/// An in-memory SwiftData container — no on-disk state, safe to spin up per test.
@MainActor
private func makeContext() throws -> ModelContext {
    let schema = Schema([Habit.self, HabitSlot.self, HabitCheckIn.self, SnoozedSlot.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config]).mainContext
}

/// A slot whose exact window times don't affect credit math.
private func dummySlot(hour: Int = 9) -> HabitSlot {
    let ref = date(year: 2000, month: 1, day: 1, hour: hour)
    return HabitSlot(start: ref, end: ref.addingTimeInterval(3600))
}

// MARK: - creditsUsed
//
// Reference point for all tests in this suite:
//   now      = Wednesday, March 5 2026 at 08:00
//   anchor   = March 1 2026 (habit created on the 1st → monthly period starts the 1st)
//   period   starts March 1
//   past psych-days before today: Mar 1, 2, 3, 4 → 4 candidate days

@Suite("SkipCreditService — creditsUsed")
struct CreditsUsedTests {

    let now    = date(year: 2026, month: 3, day: 5, hour: 8)
    // createdAt on the 1st so periodAnchor anchors the monthly period to the 1st.
    let anchor = date(year: 2026, month: 3, day: 1)

    @Test("no check-ins: every past day counts as a miss")
    @MainActor func noCheckIns() throws {
        let ctx = try makeContext()
        let habit = Habit(title: "Run", createdAt: anchor, slots: [dummySlot()], skipCreditCount: 10, skipCreditPeriod: .monthly)
        ctx.insert(habit)

        #expect(SkipCreditService.creditsUsed(for: habit, now: now) == 4)
    }

    @Test("completing a day removes it from the missed count")
    @MainActor func completedDayNotCounted() throws {
        let ctx = try makeContext()
        let habit = Habit(title: "Run", createdAt: anchor, slots: [dummySlot()], skipCreditCount: 10, skipCreditPeriod: .monthly)
        ctx.insert(habit)

        // Complete Mar 1 — leaves Mar 2, 3, 4 missed.
        ctx.insert(HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: 1, hour: 10)))

        #expect(SkipCreditService.creditsUsed(for: habit, now: now) == 3)
    }

    @Test("all past days completed → zero credits used")
    @MainActor func allDaysCompleted() throws {
        let ctx = try makeContext()
        let habit = Habit(title: "Run", createdAt: anchor, slots: [dummySlot()], skipCreditCount: 10, skipCreditPeriod: .monthly)
        ctx.insert(habit)

        for day in 1...4 {
            ctx.insert(HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: day, hour: 10)))
        }

        #expect(SkipCreditService.creditsUsed(for: habit, now: now) == 0)
    }

    @Test("today's psych-day is excluded even with no check-in")
    @MainActor func todayExcluded() throws {
        let ctx = try makeContext()
        let habit = Habit(title: "Run", createdAt: anchor, slots: [dummySlot()], skipCreditCount: 10, skipCreditPeriod: .monthly)
        ctx.insert(habit)

        // Complete Mar 1–4 but leave today (Mar 5) empty — should still be 0.
        for day in 1...4 {
            ctx.insert(HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: day, hour: 10)))
        }

        #expect(SkipCreditService.creditsUsed(for: habit, now: now) == 0)
    }

    @Test("2× daily habit: partial completion still burns (slots − completions) credits")
    @MainActor func twiceDailyPartialCompletion() throws {
        let ctx = try makeContext()
        let habit = Habit(
            title: "Run",
            createdAt: anchor,
            slots: [dummySlot(hour: 7), dummySlot(hour: 14)],  // 2 slots
            skipCreditCount: 20,
            skipCreditPeriod: .monthly
        )
        ctx.insert(habit)

        // Mar 1: 1 of 2 completions → burns 1
        ctx.insert(HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: 1, hour: 10)))
        // Mar 2, 3, 4: 0 completions each → burns 2 per day = 6

        #expect(SkipCreditService.creditsUsed(for: habit, now: now) == 7)
    }
}

// MARK: - creditsRemaining

@Suite("SkipCreditService — creditsRemaining")
struct CreditsRemainingTests {

    let now    = date(year: 2026, month: 3, day: 5, hour: 8)
    let anchor = date(year: 2026, month: 3, day: 1)

    @Test("remaining = allowance − used")
    @MainActor func simpleSubtraction() throws {
        let ctx = try makeContext()
        // 4 missed days, 5 credits → 1 remaining.
        let habit = Habit(title: "Run", createdAt: anchor, slots: [dummySlot()], skipCreditCount: 5, skipCreditPeriod: .monthly)
        ctx.insert(habit)

        #expect(SkipCreditService.creditsRemaining(for: habit, now: now) == 1)
    }

    @Test("remaining is floored at zero, never negative")
    @MainActor func flooredAtZero() throws {
        let ctx = try makeContext()
        // 4 missed days but only 2 credits allowed.
        let habit = Habit(title: "Run", createdAt: anchor, slots: [dummySlot()], skipCreditCount: 2, skipCreditPeriod: .monthly)
        ctx.insert(habit)

        #expect(SkipCreditService.creditsRemaining(for: habit, now: now) == 0)
    }

    @Test("full allowance available when no days were missed")
    @MainActor func fullAllowanceWhenNoMisses() throws {
        let ctx = try makeContext()
        let habit = Habit(title: "Run", createdAt: anchor, slots: [dummySlot()], skipCreditCount: 3, skipCreditPeriod: .monthly)
        ctx.insert(habit)

        for day in 1...4 {
            ctx.insert(HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: day, hour: 10)))
        }

        #expect(SkipCreditService.creditsRemaining(for: habit, now: now) == 3)
    }
}

// MARK: - isInPunishment

@Suite("SkipCreditService — isInPunishment")
struct IsInPunishmentTests {

    let now    = date(year: 2026, month: 3, day: 5, hour: 8)
    let anchor = date(year: 2026, month: 3, day: 1)

    @Test("punishment triggers when credits exhausted and punishment string is set")
    @MainActor func triggersWhenExhaustedWithPunishment() throws {
        let ctx = try makeContext()
        // 4 missed days, 2 credits → exhausted.
        let habit = Habit(
            title: "Run", createdAt: anchor, slots: [dummySlot()],
            skipCreditCount: 2, skipCreditPeriod: .monthly,
            punishment: "Give $20 to charity"
        )
        ctx.insert(habit)

        #expect(SkipCreditService.isInPunishment(for: habit, now: now) == true)
    }

    @Test("no punishment when credits are exhausted but punishment is nil")
    @MainActor func noPunishmentWhenNil() throws {
        let ctx = try makeContext()
        let habit = Habit(
            title: "Run", createdAt: anchor, slots: [dummySlot()],
            skipCreditCount: 2, skipCreditPeriod: .monthly,
            punishment: nil
        )
        ctx.insert(habit)

        #expect(SkipCreditService.isInPunishment(for: habit, now: now) == false)
    }

    @Test("not in punishment when credits still remain")
    @MainActor func notWhenCreditsRemain() throws {
        let ctx = try makeContext()
        let habit = Habit(
            title: "Run", createdAt: anchor, slots: [dummySlot()],
            skipCreditCount: 10, skipCreditPeriod: .monthly,
            punishment: "Give $20 to charity"
        )
        ctx.insert(habit)

        #expect(SkipCreditService.isInPunishment(for: habit, now: now) == false)
    }
}

// MARK: - Anchor-based period start

@Suite("SkipCreditService — anchor-based periodStart")
struct AnchorPeriodStartTests {

    let cal = HabitScheduling.calendar

    // MARK: Daily (anchor is ignored)

    @Test("daily period always starts at midnight of the current day")
    func dailyAlwaysMidnight() {
        let now   = date(year: 2026, month: 3, day: 5, hour: 8)
        let habit = Habit(title: "x", createdAt: date(year: 2026, month: 1, day: 17), slots: [], skipCreditCount: 0, skipCreditPeriod: .daily)
        let start = SkipCreditService.periodStart(for: habit, now: now)
        #expect(start == cal.startOfDay(for: now))
    }

    // MARK: Weekly

    // March 5 2026 = Thursday (weekday 5).

    @Test("weekly: period starts on anchor's weekday when today IS that weekday")
    func weeklyAnchorDayIsToday() {
        // anchor = Thursday March 5, now = Thursday March 5 → period starts today.
        let thursday = date(year: 2026, month: 3, day: 5)
        let habit    = Habit(title: "x", createdAt: thursday, slots: [], skipCreditCount: 0, skipCreditPeriod: .weekly)
        let start    = SkipCreditService.periodStart(for: habit, now: thursday)
        #expect(start == thursday)
    }

    @Test("weekly: period starts on the most recent past anchor weekday")
    func weeklyAnchorDayWasLastWeek() {
        // anchor = Thursday March 5, now = Monday March 9 → last Thursday = March 5.
        let thursday = date(year: 2026, month: 3, day: 5)
        let monday   = date(year: 2026, month: 3, day: 9)
        let habit    = Habit(title: "x", createdAt: thursday, slots: [], skipCreditCount: 0, skipCreditPeriod: .weekly)
        let start    = SkipCreditService.periodStart(for: habit, now: monday)
        #expect(start == thursday)
    }

    @Test("weekly: period starts within the same week when anchor weekday is earlier")
    func weeklyAnchorEarlierInWeek() {
        // anchor = Monday March 2, now = Thursday March 5 → last Monday = March 2.
        let monday   = date(year: 2026, month: 3, day: 2)
        let thursday = date(year: 2026, month: 3, day: 5)
        let habit    = Habit(title: "x", createdAt: monday, slots: [], skipCreditCount: 0, skipCreditPeriod: .weekly)
        let start    = SkipCreditService.periodStart(for: habit, now: thursday)
        #expect(start == monday)
    }

    @Test("weekly: span between start and end is exactly 7 days")
    func weeklySpanIsSevenDays() {
        let now   = date(year: 2026, month: 3, day: 5, hour: 8)
        let habit = Habit(title: "x", createdAt: date(year: 2026, month: 3, day: 2), slots: [], skipCreditCount: 0, skipCreditPeriod: .weekly)
        let start = SkipCreditService.periodStart(for: habit, now: now)
        let end   = SkipCreditService.periodEnd(for: habit, now: now)
        let diff  = cal.dateComponents([.day], from: start, to: end).day!
        #expect(diff == 7)
    }

    // MARK: Monthly

    @Test("monthly: period starts on anchor's day when today is that day")
    func monthlyAnchorDayIsToday() {
        let march5 = date(year: 2026, month: 3, day: 5)
        let habit  = Habit(title: "x", createdAt: march5, slots: [], skipCreditCount: 0, skipCreditPeriod: .monthly)
        let start  = SkipCreditService.periodStart(for: habit, now: march5)
        #expect(start == march5)
    }

    @Test("monthly: period starts this month when today is past anchor day")
    func monthlyAnchorDayEarlierInMonth() {
        // anchor = March 4, now = March 10 → period started March 4.
        let march4  = date(year: 2026, month: 3, day: 4)
        let march10 = date(year: 2026, month: 3, day: 10)
        let habit   = Habit(title: "x", createdAt: march4, slots: [], skipCreditCount: 0, skipCreditPeriod: .monthly)
        let start   = SkipCreditService.periodStart(for: habit, now: march10)
        #expect(start == march4)
    }

    @Test("monthly: period falls back to previous month when today is before anchor day")
    func monthlyAnchorDayLaterInMonth() {
        // anchor = March 20, now = March 5 → period started Feb 20.
        let march20 = date(year: 2026, month: 3, day: 20)
        let march5  = date(year: 2026, month: 3, day: 5)
        let feb20   = date(year: 2026, month: 2, day: 20)
        let habit   = Habit(title: "x", createdAt: march20, slots: [], skipCreditCount: 0, skipCreditPeriod: .monthly)
        let start   = SkipCreditService.periodStart(for: habit, now: march5)
        #expect(start == feb20)
    }

    @Test("monthly: anchor day 31 clamps to last day of February")
    func monthlyAnchor31InFebruary() {
        // anchor = March 31 (day 31), now = Feb 15 2026 → last period start = Jan 31
        // (Feb has 28 days, clamped anchor = 28, todayDay 15 < 28 → look at Jan: min(31,31)=31 → Jan 31)
        let march31 = date(year: 2026, month: 3, day: 31)
        let feb15   = date(year: 2026, month: 2, day: 15)
        let jan31   = date(year: 2026, month: 1, day: 31)
        let habit   = Habit(title: "x", createdAt: march31, slots: [], skipCreditCount: 0, skipCreditPeriod: .monthly)
        let start   = SkipCreditService.periodStart(for: habit, now: feb15)
        #expect(start == jan31)
    }

    @Test("monthly: anchor day 31 on Feb 28 starts period on Feb 28")
    func monthlyAnchor31OnFeb28() {
        // anchor = March 31 (day 31), now = Feb 28 2026 → Feb has 28 days, clamped=28, 28>=28 → Feb 28.
        let march31 = date(year: 2026, month: 3, day: 31)
        let feb28   = date(year: 2026, month: 2, day: 28)
        let habit   = Habit(title: "x", createdAt: march31, slots: [], skipCreditCount: 0, skipCreditPeriod: .monthly)
        let start   = SkipCreditService.periodStart(for: habit, now: feb28)
        #expect(start == feb28)
    }

    @Test("monthly: anchor day 31 on March 31 starts period on March 31")
    func monthlyAnchor31OnMarch31() {
        let march31 = date(year: 2026, month: 3, day: 31)
        let habit   = Habit(title: "x", createdAt: march31, slots: [], skipCreditCount: 0, skipCreditPeriod: .monthly)
        let start   = SkipCreditService.periodStart(for: habit, now: march31)
        #expect(start == march31)
    }

    // MARK: Period reset on skipCreditPeriod change

    @Test("changing skipCreditPeriod resets anchor to today, giving full credits")
    @MainActor func periodResetOnEdit() throws {
        let ctx = try makeContext()
        // Habit created March 1 (monthly), misses Mar 1–4 (4 credits used of 5).
        let createdAt = date(year: 2026, month: 3, day: 1)
        let now       = date(year: 2026, month: 3, day: 5, hour: 8)
        let habit     = Habit(title: "Run", createdAt: createdAt, slots: [dummySlot()], skipCreditCount: 5, skipCreditPeriod: .monthly)
        ctx.insert(habit)
        #expect(SkipCreditService.creditsUsed(for: habit, now: now) == 4)

        // Simulate user editing: change period to weekly, anchor resets to today.
        habit.skipCreditPeriod = .weekly
        habit.periodAnchor     = now

        // Credits used should now be 0 — the new period started today.
        #expect(SkipCreditService.creditsUsed(for: habit, now: now) == 0)
        #expect(SkipCreditService.creditsRemaining(for: habit, now: now) == 5)
    }
}

// MARK: - clampedMonthDay helper

@Suite("SkipCreditService — clampedMonthDay")
struct ClampedMonthDayTests {

    let cal = HabitScheduling.calendar

    @Test("target day within month returns exact date")
    func withinMonth() {
        let ref    = date(year: 2026, month: 3, day: 1)
        let result = SkipCreditService.clampedMonthDay(15, inMonthOf: ref, cal: cal)!
        #expect(result == date(year: 2026, month: 3, day: 15))
    }

    @Test("target day 31 in February clamps to 28")
    func clampFeb() {
        let ref    = date(year: 2026, month: 2, day: 1)
        let result = SkipCreditService.clampedMonthDay(31, inMonthOf: ref, cal: cal)!
        #expect(result == date(year: 2026, month: 2, day: 28))
    }

    @Test("target day 31 in March returns March 31")
    func march31() {
        let ref    = date(year: 2026, month: 3, day: 1)
        let result = SkipCreditService.clampedMonthDay(31, inMonthOf: ref, cal: cal)!
        #expect(result == date(year: 2026, month: 3, day: 31))
    }

    @Test("target day 30 in February clamps to 28")
    func clampFeb30() {
        let ref    = date(year: 2026, month: 2, day: 1)
        let result = SkipCreditService.clampedMonthDay(30, inMonthOf: ref, cal: cal)!
        #expect(result == date(year: 2026, month: 2, day: 28))
    }
}
