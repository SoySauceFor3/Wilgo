import Foundation
import SwiftData
import Testing

@testable import Wilgo

// MARK: - Helpers (file-private, mirror SlotQueries.swift)

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

private func timeOfDay(hour: Int, minute: Int = 0) -> Date {
    date(year: 2000, month: 1, day: 1, hour: hour, minute: minute)
}

@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema([Habit.self, Slot.self, HabitCheckIn.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

private func makeSlot(startHour: Int, endHour: Int) -> Slot {
    Slot(start: timeOfDay(hour: startHour), end: timeOfDay(hour: endHour))
}

@MainActor
private func makeHabit(
    in ctx: ModelContext,
    title: String = "A",
    slots: [Slot] = [],
    goalCountPerDay: Int = 2
) -> Habit {
    let habit = Habit(
        title: title, slots: slots, skipCreditCount: 0, cycle: .daily,
        goalCountPerDay: goalCountPerDay)
    ctx.insert(habit)
    for slot in slots { ctx.insert(slot) }
    return habit
}

@Suite("HabitAndSlot tests", .serialized)  // seems that parallelly running the test create some mysterious bug
struct HabitAndSlotTests {
    // MARK: - HabitAndSlot.current
    @Suite("HabitAndSlot — current")
    final class HabitAndSlotCurrentTests {

        // Frozen instant used as the injectable clock for the entire suite.
        // All slot startToday/endToday values are anchored to this date, and
        // noonNow (passed as `now`) falls within the wide window (00:00–23:00).
        private static let frozenNoon = date(year: 2025, month: 6, day: 15, hour: 12)

        private let savedNow = HabitScheduling.now
        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)

        init() {
            UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey)
            HabitScheduling.now = { HabitAndSlotCurrentTests.frozenNoon }
        }

        deinit {
            let savedNow = savedNow
            let savedOffset = savedOffset
            UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey)
            HabitScheduling.now = savedNow
        }

        private func wideSlot(endHour: Int = 23) -> Slot {
            makeSlot(startHour: 0, endHour: endHour)
        }

        @Test("empty habits → empty")
        @MainActor func emptyHabits() throws {
            let result = HabitAndSlot.current(habits: [])
            #expect(result.isEmpty)
        }

        @Test("habits whose daily goal has been met → empty")
        @MainActor func habitsWithMetDailyGoal() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, slots: [wideSlot()])
            ctx.insert(HabitCheckIn(habit: habit, createdAt: HabitScheduling.now()))  // met daily goal
            let result = HabitAndSlot.current(habits: [habit])
            #expect(result.isEmpty)
        }

        @Test("overlap with now → habit included")
        @MainActor func overlapWithNowIncluded() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, slots: [wideSlot()])
            let result = HabitAndSlot.current(habits: [habit])
            #expect(result.count == 1)
            #expect(result[0].0 === habit)  // habit is included
        }

        @Test("more urgent slot (less remaining fraction) sorts first")
        @MainActor func sortsByRemainingFraction() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habitA = makeHabit(in: ctx, title: "A", slots: [wideSlot(endHour: 23)])
            let habitB = makeHabit(in: ctx, title: "B", slots: [wideSlot(endHour: 22)])
            let result = HabitAndSlot.current(habits: [habitA, habitB])
            #expect(result.count == 2)
            #expect(result[0].0 === habitB)  // B (end=22) is more urgent
            #expect(result[1].0 === habitA)
        }
    }

    // MARK: - HabitAndSlot.upcoming
    @Suite("HabitAndSlot — upcoming")
    final class HabitAndSlotUpcomingTests {

        // // Frozen instant used as the injectable clock for the entire suite.
        // private static let fakeNow = date(year: 2025, month: 6, day: 15, hour: 0)

        // private let savedNow = HabitScheduling.now
        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)

        init() {
            UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey)
            // HabitScheduling.now = { return HabitAndSlotUpcomingTests.fakeNow }
        }

        deinit {
            // let savedNow = savedNow
            let savedOffset = savedOffset
            UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey)
            // HabitScheduling.now = savedNow
        }

        @Test("empty habits → empty")
        @MainActor func emptyHabits() throws {
            let result = HabitAndSlot.upcoming(
                habits: [], after: date(year: 2000, month: 1, day: 1, hour: 0))
            #expect(result.isEmpty)
        }

        @Test("habit with no slots → omitted")
        @MainActor func habitWithNoSlotsOmitted() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx)
            let result = HabitAndSlot.upcoming(
                habits: [habit], after: date(year: 2000, month: 1, day: 1, hour: 0))
            #expect(result.isEmpty)
        }

        @Test("habit with a future slot → included")
        @MainActor func futureSlotIncluded() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, slots: [makeSlot(startHour: 14, endHour: 15)])  // afternoon is later than noon.
            let result = HabitAndSlot.upcoming(
                habits: [habit], after: date(year: 2000, month: 1, day: 1, hour: 0))
            #expect(result.count == 1)
            #expect(result[0].0 === habit)
        }

        @Test("habit with met daily goal → habit omitted")
        @MainActor func habitWithMetDailyGoalOmitted() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(
                in: ctx, slots: [makeSlot(startHour: 9, endHour: 10)], goalCountPerDay: 1)
            ctx.insert(
                HabitCheckIn(habit: habit, createdAt: date(year: 2000, month: 1, day: 1, hour: 0)))
            let result = HabitAndSlot.upcoming(
                habits: [habit], after: date(year: 2000, month: 1, day: 1, hour: 0))
            #expect(result.isEmpty)
        }

        @Test("multiple habits: sorted by ascending slot start time")
        @MainActor func sortedBySlotStartTime() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            // Insert afternoon-first habit to prove we're not relying on insertion order.
            let habitLate = makeHabit(
                in: ctx, title: "Late", slots: [makeSlot(startHour: 15, endHour: 16)])
            let habitEarly = makeHabit(
                in: ctx, title: "Early", slots: [makeSlot(startHour: 13, endHour: 14)])
            let result = HabitAndSlot.upcoming(
                habits: [habitLate, habitEarly], after: date(year: 2000, month: 1, day: 1, hour: 0))
            #expect(result.count == 2)

            #expect(result[0] == (habitEarly, habitEarly.slots[0]))
            #expect(result[1] == (habitLate, habitLate.slots[0]))
        }

        @Test("only first future slot per habit is returned")
        @MainActor func onlyFirstFutureSlot() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let morning = makeSlot(startHour: 7, endHour: 8)
            let afternoon = makeSlot(startHour: 14, endHour: 15)
            let habit = makeHabit(in: ctx, slots: [morning, afternoon])
            let result = HabitAndSlot.upcoming(
                habits: [habit], after: date(year: 2000, month: 1, day: 1, hour: 0))
            #expect(result.count == 1)
            #expect(result[0] == (habit, morning))
        }
    }

    @Suite("HabitAndSlot — nextTransitionDate")
    final class HabitAndSlotNextTransitionDateTests {

        // Frozen instant used as the injectable clock for the entire suite.
        private static let fakeNow = date(year: 2025, month: 6, day: 15, hour: 6)
        private static let nextPsychDayStart = date(year: 2025, month: 6, day: 16, hour: 0)

        private let savedNow = HabitScheduling.now
        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)

        init() {
            UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey)
            HabitScheduling.now = { return HabitAndSlotNextTransitionDateTests.fakeNow }
        }

        deinit {
            let savedNow = savedNow
            let savedOffset = savedOffset
            UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey)
            HabitScheduling.now = savedNow
        }

        @Test("empty habits → returns the next psychDay boundary")
        @MainActor func emptyHabitsReturnsPsychDayBoundary() throws {
            print("111HabitScheduling.now() = \(HabitScheduling.now())")
            let result = HabitAndSlot.nextTransitionDate(habits: [])
            #expect(result == HabitAndSlotNextTransitionDateTests.nextPsychDayStart)
        }

        @Test("simple one slot case")
        @MainActor func oneSlotCase() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, slots: [makeSlot(startHour: 9, endHour: 10)])
            let result = HabitAndSlot.nextTransitionDate(habits: [habit])
            #expect(result != nil)
            #expect(result! == date(year: 2025, month: 6, day: 15, hour: 9))
        }

        @Test("start is already passed now")
        @MainActor func startIsAlreadyPassedNow() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, slots: [makeSlot(startHour: 4, endHour: 10)])
            let result = HabitAndSlot.nextTransitionDate(habits: [habit])
            #expect(result != nil)
            #expect(result! == date(year: 2025, month: 6, day: 15, hour: 10))
        }

        @Test("multiple slots case")
        @MainActor func multipleSlotsCase() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(
                in: ctx,
                slots: [makeSlot(startHour: 4, endHour: 10), makeSlot(startHour: 8, endHour: 11)])
            let result = HabitAndSlot.nextTransitionDate(habits: [habit])
            #expect(result != nil)
            #expect(result! == date(year: 2025, month: 6, day: 15, hour: 8))
        }
    }
}
