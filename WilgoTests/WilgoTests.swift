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
//   now  = Wednesday, March 5 2026 at 08:00
//   period (monthly) starts March 1
//   past psych-days before today: Mar 1, 2, 3, 4 → 4 candidate days

@Suite("SkipCreditService — creditsUsed")
struct CreditsUsedTests {

    let now = date(year: 2026, month: 3, day: 5, hour: 8)

    @Test("no check-ins: every past day counts as a miss")
    @MainActor func noCheckIns() throws {
        let ctx = try makeContext()
        let habit = Habit(title: "Run", slots: [dummySlot()], skipCreditCount: 10, skipCreditPeriod: .monthly)
        ctx.insert(habit)

        #expect(SkipCreditService.creditsUsed(for: habit, now: now) == 4)
    }

    @Test("completing a day removes it from the missed count")
    @MainActor func completedDayNotCounted() throws {
        let ctx = try makeContext()
        let habit = Habit(title: "Run", slots: [dummySlot()], skipCreditCount: 10, skipCreditPeriod: .monthly)
        ctx.insert(habit)

        // Complete Mar 1 — leaves Mar 2, 3, 4 missed.
        ctx.insert(HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: 1, hour: 10)))

        #expect(SkipCreditService.creditsUsed(for: habit, now: now) == 3)
    }

    @Test("all past days completed → zero credits used")
    @MainActor func allDaysCompleted() throws {
        let ctx = try makeContext()
        let habit = Habit(title: "Run", slots: [dummySlot()], skipCreditCount: 10, skipCreditPeriod: .monthly)
        ctx.insert(habit)

        for day in 1...4 {
            ctx.insert(HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: day, hour: 10)))
        }

        #expect(SkipCreditService.creditsUsed(for: habit, now: now) == 0)
    }

    @Test("today's psych-day is excluded even with no check-in")
    @MainActor func todayExcluded() throws {
        let ctx = try makeContext()
        let habit = Habit(title: "Run", slots: [dummySlot()], skipCreditCount: 10, skipCreditPeriod: .monthly)
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

    let now = date(year: 2026, month: 3, day: 5, hour: 8)

    @Test("remaining = allowance − used")
    @MainActor func simpleSubtraction() throws {
        let ctx = try makeContext()
        // 4 missed days, 5 credits → 1 remaining.
        let habit = Habit(title: "Run", slots: [dummySlot()], skipCreditCount: 5, skipCreditPeriod: .monthly)
        ctx.insert(habit)

        #expect(SkipCreditService.creditsRemaining(for: habit, now: now) == 1)
    }

    @Test("remaining is floored at zero, never negative")
    @MainActor func flooredAtZero() throws {
        let ctx = try makeContext()
        // 4 missed days but only 2 credits allowed.
        let habit = Habit(title: "Run", slots: [dummySlot()], skipCreditCount: 2, skipCreditPeriod: .monthly)
        ctx.insert(habit)

        #expect(SkipCreditService.creditsRemaining(for: habit, now: now) == 0)
    }

    @Test("full allowance available when no days were missed")
    @MainActor func fullAllowanceWhenNoMisses() throws {
        let ctx = try makeContext()
        let habit = Habit(title: "Run", slots: [dummySlot()], skipCreditCount: 3, skipCreditPeriod: .monthly)
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

    let now = date(year: 2026, month: 3, day: 5, hour: 8)

    @Test("punishment triggers when credits exhausted and punishment string is set")
    @MainActor func triggersWhenExhaustedWithPunishment() throws {
        let ctx = try makeContext()
        // 4 missed days, 2 credits → exhausted.
        let habit = Habit(
            title: "Run", slots: [dummySlot()],
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
            title: "Run", slots: [dummySlot()],
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
            title: "Run", slots: [dummySlot()],
            skipCreditCount: 10, skipCreditPeriod: .monthly,
            punishment: "Give $20 to charity"
        )
        ctx.insert(habit)

        #expect(SkipCreditService.isInPunishment(for: habit, now: now) == false)
    }
}

// MARK: - Period boundaries

@Suite("SkipCreditService — period boundaries")
struct PeriodBoundaryTests {

    let now = date(year: 2026, month: 3, day: 5, hour: 8)
    let cal = Calendar.current

    @Test("daily period starts at midnight of the current day")
    func dailyStart() {
        let start = SkipCreditService.periodStart(for: .daily, now: now)
        #expect(start == cal.startOfDay(for: now))
    }

    @Test("daily period ends at midnight of the next day")
    func dailyEnd() {
        let end = SkipCreditService.periodEnd(for: .daily, now: now)
        let expected = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        #expect(end == expected)
    }

    @Test("monthly period starts on the first of the current month")
    func monthlyStart() {
        let start = SkipCreditService.periodStart(for: .monthly, now: now)
        let expected = date(year: 2026, month: 3, day: 1)
        #expect(start == expected)
    }

    @Test("monthly period ends on the first of the next month")
    func monthlyEnd() {
        let end = SkipCreditService.periodEnd(for: .monthly, now: now)
        let expected = date(year: 2026, month: 4, day: 1)
        #expect(end == expected)
    }

    @Test("weekly period start and end are exactly 7 days apart")
    func weeklySpan() {
        let start = SkipCreditService.periodStart(for: .weekly, now: now)
        let end = SkipCreditService.periodEnd(for: .weekly, now: now)
        let diff = cal.dateComponents([.day], from: start, to: end).day!
        #expect(diff == 7)
    }

    @Test("weekly period start is a natural week boundary for the current calendar")
    func weeklyStartIsWeekBoundary() {
        let start = SkipCreditService.periodStart(for: .weekly, now: now)
        let expectedComps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let expected = cal.date(from: expectedComps)!
        #expect(start == expected)
    }
}
