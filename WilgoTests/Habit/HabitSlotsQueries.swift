import Foundation
import SwiftData
import Testing

@testable import Wilgo

// MARK: - Helpers

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

/// A time-of-day reference date. Only hour and minute are meaningful — the same
/// semantics Slot uses for its start/end fields.
private func timeOfDay(hour: Int, minute: Int = 0) -> Date {
    date(year: 2000, month: 1, day: 1, hour: hour, minute: minute)
}

/// Returns a fresh in-memory ModelContainer.
///
/// IMPORTANT: callers must keep the returned container alive (e.g. as a local `let container =`)
/// for the entire test — ModelContext holds only a *weak* back-reference to its container in
/// SwiftData; if the container is released, any subsequent context operation crashes.
@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema([Habit.self, Slot.self, HabitCheckIn.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

/// Creates a Slot (uninserted). Pass the slot to `makeHabit(in:slots:)` so the
/// correct insertion order is always observed.
private func makeSlot(startHour: Int, endHour: Int) -> Slot {
    Slot(start: timeOfDay(hour: startHour), end: timeOfDay(hour: endHour))
}

/// Creates a habit and inserts it and all its slots into `ctx`.
/// Slots must be explicitly inserted — SwiftData does not cascade-insert them automatically.
@MainActor
private func makeHabit(
    in ctx: ModelContext,
    title: String = "A",
    goalCountPerDay: Int = 1,
    slots: [Slot] = [],
    skipCreditCount: Int = 0,
    cycle: Cycle = .daily
) -> Habit {
    let habit = Habit(
        title: title, slots: slots, skipCreditCount: skipCreditCount, cycle: cycle,
        goalCountPerDay: goalCountPerDay)
    ctx.insert(habit)
    for slot in slots { ctx.insert(slot) }
    return habit
}

// MARK: - UserDefaults isolation
//
// HabitScheduling.dayStartHourOffset reads UserDefaults.standard live. In a
// unit-test host the standard suite IS the real app's suite (shared with device
// data), so we must save and restore the value around every test.
//
// Using class-based suites gives us `deinit` which Swift Testing calls after
// each individual test, making it the right teardown hook.

// MARK: - completedCount
//
// Counts check-ins whose psychDay matches psychDay(for: now).
// Tests pin dayStartHourOffset = 0 (midnight day-start) so psychDay is simply
// midnight of the local calendar day, regardless of the device's Settings value.

@Suite("Habit slots queries", .serialized)
struct SlotsQueriesTests {
    @Suite("Habit — completedCount")
    final class HabitCompletedCountTests {

        // Captured before init() overwrites it — restored in deinit.
        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)
        init() { UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey) }
        deinit { UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey) }

        let psychDay = date(year: 2026, month: 3, day: 5)

        @Test("no check-ins → 0")
        @MainActor func noCheckIns() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, slots: [makeSlot(startHour: 9, endHour: 10)])
            #expect(habit.completedCount(for: psychDay) == 0)
        }

        @Test("one check-in on the same psych day → 1")
        @MainActor func oneCheckInToday() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, slots: [makeSlot(startHour: 9, endHour: 10)])
            ctx.insert(
                HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: 5, hour: 9)))
            #expect(habit.completedCount(for: psychDay) == 1)
        }

        @Test("two check-ins on the same psych day → 2")
        @MainActor func twoCheckInsToday() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(
                in: ctx,
                slots: [
                    makeSlot(startHour: 7, endHour: 8),
                    makeSlot(startHour: 14, endHour: 15),
                ])
            ctx.insert(
                HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: 5, hour: 7)))
            ctx.insert(
                HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: 5, hour: 14)))
            #expect(habit.completedCount(for: psychDay) == 2)
        }

        @Test("check-in on a different psych day is not counted")
        @MainActor func checkInYesterdayNotCounted() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, slots: [makeSlot(startHour: 9, endHour: 10)])
            ctx.insert(
                HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: 4, hour: 9)))
            #expect(habit.completedCount(for: psychDay) == 0)
        }

        @Test("only today's check-ins count when mixed with other days")
        @MainActor func onlyTodayCheckInsCounted() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(
                in: ctx,
                slots: [
                    makeSlot(startHour: 7, endHour: 8),
                    makeSlot(startHour: 14, endHour: 15),
                ])
            ctx.insert(
                HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: 4, hour: 9)))  // yesterday
            ctx.insert(
                HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: 5, hour: 9)))  // today
            #expect(habit.completedCount(for: psychDay) == 1)
        }
    }

    // MARK: - unfinishedSlots
    //
    // Drops the first completedCount(now:) slots from the sorted slot list.
    // Sort order is by startToday (resolved using the real clock), but relative order
    // between two distinct hours is stable regardless of when tests run.

    @Suite("Habit — unfinishedSlots")
    final class HabitUnfinishedSlotsTests {

        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)
        init() { UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey) }
        deinit { UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey) }

        let psychDay = date(year: 2026, month: 3, day: 5)

        @Test("no check-ins → all slots returned")
        @MainActor func noCheckInsAllSlots() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(
                in: ctx,
                slots: [
                    makeSlot(startHour: 7, endHour: 8),
                    makeSlot(startHour: 14, endHour: 15),
                ])
            #expect(habit.unfinishedSlots(for: psychDay).count == 2)
        }

        @Test("slots are returned in ascending time order")
        @MainActor func slotsReturnedInSortedOrder() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            // Insert afternoon slot first so we can verify sorting, not insertion order.
            let afternoon = makeSlot(startHour: 14, endHour: 15)
            let morning = makeSlot(startHour: 7, endHour: 8)
            let habit = makeHabit(in: ctx, slots: [afternoon, morning])
            let remaining = habit.unfinishedSlots(for: psychDay)
            #expect(remaining.count == 2)
            // The morning slot (hour 7) must sort before the afternoon slot (hour 14).
            let firstHour = Calendar.current.component(.hour, from: remaining[0].start)
            let secondHour = Calendar.current.component(.hour, from: remaining[1].start)
            #expect(firstHour < secondHour)
        }

        @Test("one check-in today drops the first (earliest) slot")
        @MainActor func oneCheckInDropsFirst() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(
                in: ctx,
                slots: [
                    makeSlot(startHour: 7, endHour: 8),
                    makeSlot(startHour: 14, endHour: 15),
                ])
            ctx.insert(
                HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: 5, hour: 7)))
            let remaining = habit.unfinishedSlots(for: psychDay)
            #expect(remaining.count == 1)
            // Only the afternoon slot should remain.
            #expect(Calendar.current.component(.hour, from: remaining[0].start) == 14)
        }

        @Test("all slots completed → empty")
        @MainActor func allCompletedReturnsEmpty() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(
                in: ctx,
                slots: [
                    makeSlot(startHour: 7, endHour: 8),
                    makeSlot(startHour: 14, endHour: 15),
                ])
            ctx.insert(
                HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: 5, hour: 7)))
            ctx.insert(
                HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: 5, hour: 14)))
            #expect(habit.unfinishedSlots(for: psychDay).isEmpty)
        }

        @Test("no slots → empty")
        @MainActor func noSlotsReturnsEmpty() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx)
            #expect(habit.unfinishedSlots(for: psychDay).isEmpty)
        }

        @Test("check-in on a different psych day does not reduce remaining count")
        @MainActor func yesterdayCheckInIgnored() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, slots: [makeSlot(startHour: 9, endHour: 10)])
            ctx.insert(
                HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: 4, hour: 9)))
            #expect(habit.unfinishedSlots(for: psychDay).count == 1)
        }
    }

    @Suite("Habit — hasMetDailyGoal")
    final class HabitMetDailyGoalTests {

        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)
        init() { UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey) }
        deinit { UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey) }

        let psychDay = date(year: 2026, month: 3, day: 5)

        @Test("no check-ins → false")
        @MainActor func noCheckInsIsNotMet() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, goalCountPerDay: 1)
            #expect(habit.hasMetDailyGoal(for: psychDay) == false)
        }

        @Test("partial completion → false")
        @MainActor func partialCompletionIsUnfinished() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(
                in: ctx,
                goalCountPerDay: 2
            )
            ctx.insert(
                HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: 5, hour: 7)))
            #expect(habit.hasMetDailyGoal(for: psychDay) == false)
        }

        @Test("dailyGoalIsMet, goalCountPerDay is 1")
        @MainActor func dailyGoalIsMet() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, goalCountPerDay: 1)
            ctx.insert(
                HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: 5, hour: 9)))
            #expect(habit.hasMetDailyGoal(for: psychDay) == true)
        }

        @Test("dailyGoalIsMet, goalCountPerDay is 2")
        @MainActor func dailyGoalIsMetWithMultipleCheckIns() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, goalCountPerDay: 2)
            ctx.insert(
                HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: 5, hour: 9)))
            ctx.insert(
                HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: 5, hour: 10)))
            #expect(habit.hasMetDailyGoal(for: psychDay) == true)
        }

        @Test("edge case, goalCountPerDay is 0 → true")
        @MainActor func goalCountPerDayIs0IsMet() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, goalCountPerDay: 0)
            #expect(habit.hasMetDailyGoal(for: psychDay) == true)
        }
    }

    // MARK: - firstCurrentSlot

    @Suite("Habit — firstCurrentSlot")
    final class HabitFirstCurrentSlotTests {
        // Frozen instant used as the injectable clock for the entire suite.
        private static let fakeNow = date(year: 2000, month: 1, day: 1, hour: 12)

        private let savedNow = HabitScheduling.now
        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)

        init() {
            UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey)
            HabitScheduling.now = { return HabitFirstCurrentSlotTests.fakeNow }
        }

        deinit {
            let savedNow = savedNow
            let savedOffset = savedOffset
            UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey)
            HabitScheduling.now = savedNow
        }

        private func wideSlot(startHour: Int = 0) -> Slot {
            makeSlot(startHour: startHour, endHour: 23)
        }

        @Test("slot in window, no exclude → returned")
        @MainActor func slotInWindowReturned() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, slots: [wideSlot()])
            #expect(
                habit.firstCurrentSlot(
                    now: HabitScheduling.now(), excluding: []) != nil)
        }

        @Test("only slot is excluded → nil")
        @MainActor func excludedSlotReturnsNil() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let s = wideSlot()
            let habit = makeHabit(in: ctx, slots: [s])
            #expect(
                habit.firstCurrentSlot(
                    now: HabitScheduling.now(), excluding: [s]) == nil)
        }

        @Test("first slot excluded → second slot returned")
        @MainActor func excludedFirstSlotReturnsSecond() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            // s1 sorts before s2 (lower start hour). Both windows span wide.
            let s1 = wideSlot(startHour: 0)
            let s2 = wideSlot(startHour: 1)
            let habit = makeHabit(in: ctx, slots: [s1, s2])
            let result = habit.firstCurrentSlot(
                now: HabitScheduling.now(), excluding: [s1])
            #expect(result != nil)
            #expect(result?.start == s2.start)
        }

        @Test("slot on the same day, slot in window → returned")
        @MainActor func slotOnSameDayInWindow() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let s1 = makeSlot(startHour: 11, endHour: 13)
            let habit = makeHabit(in: ctx, slots: [s1])
            let result = habit.firstCurrentSlot(
                now: HabitScheduling.now(), excluding: [])
            #expect(result != nil)
            #expect(result == s1)
        }

        @Test("slot on the same day, slot not in window,  → nil")
        @MainActor func slotOnSameDayNotInWindow() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let s1 = makeSlot(startHour: 9, endHour: 10)
            let habit = makeHabit(in: ctx, slots: [s1])
            let result = habit.firstCurrentSlot(
                now: HabitScheduling.now(), excluding: [])
            #expect(result == nil)
        }

        @Test("slot cross midnight, slot in window, no exclude → returned")
        @MainActor func crossMidnightSlotInWindow() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let s1 = makeSlot(startHour: 23, endHour: 13)
            let habit = makeHabit(in: ctx, slots: [s1])
            let result = habit.firstCurrentSlot(
                now: HabitScheduling.now(), excluding: [])
            #expect(result != nil)
            #expect(result == s1)
        }

        @Test("slot cross midnight, slot not in window  → nil")
        @MainActor func crossMidnightSlotNotInWindow() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let s1 = makeSlot(startHour: 23, endHour: 11)
            let habit = makeHabit(in: ctx, slots: [s1])
            let result = habit.firstCurrentSlot(
                now: HabitScheduling.now(), excluding: [])
            #expect(result == nil)
        }
    }

    // MARK: - firstFutureSlot

    @Suite("Habit — firstSlotAfter")
    final class HabitFirstSlotAfterTests {
        private let savedNow = HabitScheduling.now
        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)

        init() {
            UserDefaults.standard.set(9, forKey: AppSettings.dayStartHourKey)
        }

        deinit {
            // let savedNow = savedNow
            let savedOffset = savedOffset
            UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey)
            // HabitScheduling.now = savedNow
        }

        @Test("slot in the future → returned")
        @MainActor func futureSlotReturned() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let s1 = makeSlot(startHour: 14, endHour: 15)
            let habit = makeHabit(in: ctx, slots: [s1])
            let result = habit.firstSlotAfter(time: date(year: 2000, month: 1, day: 1, hour: 12))
            #expect(result == s1)
        }

        @Test("earliest future slot returned when multiple slots exist")
        @MainActor func earliestFutureSlotReturned() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let s1 = makeSlot(startHour: 13, endHour: 8)
            let s2 = makeSlot(startHour: 14, endHour: 15)
            let habit = makeHabit(in: ctx, slots: [s2, s1])
            let result = habit.firstSlotAfter(time: date(year: 2000, month: 1, day: 1, hour: 12))
            #expect(result == s1)
        }

        @Test("checkIns do not matter")
        @MainActor func checkInsDoNotMatter() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let s1 = makeSlot(startHour: 15, endHour: 16)
            let habit = makeHabit(in: ctx, slots: [s1])
            ctx.insert(
                HabitCheckIn(habit: habit, createdAt: date(year: 2000, month: 1, day: 1, hour: 12)))
            let result = habit.firstSlotAfter(time: date(year: 2000, month: 1, day: 1, hour: 12))
            #expect(result == s1)
        }

        @Test("no slots → nil")
        @MainActor func noSlotsReturnsNil() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx)
            let result = habit.firstSlotAfter(time: date(year: 2000, month: 1, day: 1, hour: 12))
            #expect(result == nil)
        }

        @Test("past slot is excluded")
        @MainActor func pastSlotExcluded() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let morning = makeSlot(startHour: 7, endHour: 8)
            let afternoon = makeSlot(startHour: 14, endHour: 15)
            let habit = makeHabit(in: ctx, slots: [morning, afternoon])
            let result = habit.firstSlotAfter(time: date(year: 2000, month: 1, day: 1, hour: 12))
            #expect(result == afternoon)
        }

        @Test("cross midnight slot but later in terms of the psych day")
        @MainActor func crossMidnightSlotButLaterInTermsOfThePsychDay() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let morning = makeSlot(startHour: 7, endHour: 8)
            let habit = makeHabit(in: ctx, slots: [morning])
            let result = habit.firstSlotAfter(time: date(year: 2000, month: 1, day: 1, hour: 12))
            #expect(result == morning)
        }

        @Test("cross midnight slot but not later in terms of the psych day")
        @MainActor func crossMidnightSlotButNotLaterInTermsOfThePsychDay() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let morning = makeSlot(startHour: 10, endHour: 8)
            let habit = makeHabit(in: ctx, slots: [morning])
            let result = habit.firstSlotAfter(time: date(year: 2000, month: 1, day: 1, hour: 12))
            #expect(result == nil)
        }
    }
}
