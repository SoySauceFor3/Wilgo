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
    let schema = Schema([Habit.self, HabitSlot.self, HabitCheckIn.self, SnoozedSlot.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

private func makeSlot(startHour: Int, endHour: Int) -> HabitSlot {
    HabitSlot(start: timeOfDay(hour: startHour), end: timeOfDay(hour: endHour))
}

@MainActor
private func makeHabit(
    in ctx: ModelContext,
    title: String = "A",
    slots: [HabitSlot] = []
) -> Habit {
    let habit = Habit(title: title, slots: slots, skipCreditCount: 0, cycle: .daily, goalCountPerDay: 2)
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

        private func wideSlot(endHour: Int = 23) -> HabitSlot {
            makeSlot(startHour: 0, endHour: endHour)
        }

        @Test("empty habits → empty")
        @MainActor func emptyHabits() throws {
            let result = HabitAndSlot.current(habits: [], snoozedSlots: [])
            #expect(result.isEmpty)
        }

        @Test("habit with no slots → omitted")
        @MainActor func habitWithNoSlotsOmitted() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx)
            let result = HabitAndSlot.current(habits: [habit], snoozedSlots: [])
            #expect(result.isEmpty)
        }

        @Test("active slot (wide window) → habit included")
        @MainActor func activeSlotIncluded() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, slots: [wideSlot()])
            let result = HabitAndSlot.current(habits: [habit], snoozedSlots: [])
            #expect(result.count == 1)
            #expect(result[0].0 === habit)
        }

        @Test("snoozed slot → habit excluded")
        @MainActor func snoozedSlotExcluded() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let s = wideSlot()
            let habit = makeHabit(in: ctx, slots: [s])
            let snooze = SnoozedSlot(habit: habit, slot: s)
            ctx.insert(snooze)
            let result = HabitAndSlot.current(
                habits: [habit], snoozedSlots: [snooze])
            #expect(result.isEmpty)
        }

        @Test("first slot snoozed → second slot still active")
        @MainActor func snoozedFirstSlotFallsBackToSecond() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let s1 = wideSlot(endHour: 22)
            let s2 = wideSlot(endHour: 23)
            let habit = makeHabit(in: ctx, slots: [s1, s2])
            let snooze = SnoozedSlot(habit: habit, slot: s1)
            ctx.insert(snooze)
            let result = HabitAndSlot.current(
                habits: [habit], snoozedSlots: [snooze])
            #expect(result.count == 1)
        }

        // Sorting proof: remainingFraction(end=22) < remainingFraction(end=23) for any t > 0.
        // (22-t)/22 < (23-t)/23 ↔ 23(22-t) < 22(23-t) ↔ -23t < -22t ↔ t > 0. ✓
        // Slot ending at 22:00 is more urgent (less remaining fraction) than one ending at 23:00.
        @Test("more urgent slot (less remaining fraction) sorts first")
        @MainActor func sortsByRemainingFraction() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habitA = makeHabit(in: ctx, title: "A", slots: [wideSlot(endHour: 23)])
            let habitB = makeHabit(in: ctx, title: "B", slots: [wideSlot(endHour: 22)])
            let result = HabitAndSlot.current(
                habits: [habitA, habitB], snoozedSlots: [])
            #expect(result.count == 2)
            #expect(result[0].0 === habitB)  // B (end=22) is more urgent
            #expect(result[1].0 === habitA)
        }
    }

    // MARK: - HabitAndSlot.upcoming
    @Suite("HabitAndSlot — upcoming")
    final class HabitAndSlotUpcomingTests {

        // Frozen instant used as the injectable clock for the entire suite.
        private static let fakeNow = date(year: 2025, month: 6, day: 15, hour: 0)

        private let savedNow = HabitScheduling.now
        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)

        init() {
            UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey)
            HabitScheduling.now = { return HabitAndSlotUpcomingTests.fakeNow }
        }

        deinit {
            let savedNow = savedNow
            let savedOffset = savedOffset
            UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey)
            HabitScheduling.now = savedNow
        }

        @Test("empty habits → empty")
        @MainActor func emptyHabits() throws {
            let result = HabitAndSlot.upcoming(habits: [])
            #expect(result.isEmpty)
        }

        @Test("habit with no slots → omitted")
        @MainActor func habitWithNoSlotsOmitted() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx)
            let result = HabitAndSlot.upcoming(habits: [habit])
            #expect(result.isEmpty)
        }

        @Test("habit with a future slot → included")
        @MainActor func futureSlotIncluded() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, slots: [makeSlot(startHour: 14, endHour: 15)])  // afternoon is later than noon.
            let result = HabitAndSlot.upcoming(habits: [habit])
            #expect(result.count == 1)
            #expect(result[0].0 === habit)
        }

        @Test("all slots completed today → habit omitted")
        @MainActor func completedTodayOmitted() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, slots: [makeSlot(startHour: 9, endHour: 10)])
            ctx.insert(HabitCheckIn(habit: habit, createdAt: HabitAndSlotUpcomingTests.fakeNow))
            let result = HabitAndSlot.upcoming(habits: [habit])
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
            let result = HabitAndSlot.upcoming(habits: [habitLate, habitEarly])
            #expect(result.count == 2)
            // Morning (hour 7) must precede afternoon (hour 14).
            let firstHour = Calendar.current.component(.hour, from: result[0].1.start)
            let secondHour = Calendar.current.component(.hour, from: result[1].1.start)
            #expect(firstHour < secondHour)
        }

        @Test("only first future slot per habit is returned")
        @MainActor func onlyFirstFutureSlot() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let morning = makeSlot(startHour: 7, endHour: 8)
            let afternoon = makeSlot(startHour: 14, endHour: 15)
            let habit = makeHabit(in: ctx, slots: [morning, afternoon])
            let result = HabitAndSlot.upcoming(habits: [habit])
            #expect(result.count == 1)
            #expect(Calendar.current.component(.hour, from: result[0].1.start) == 7)
        }
    }

    // // MARK: - HabitAndSlot.missed
    // //
    // // `endToday` is computed against the real clock. Passing `now` one day ahead of
    // // the real clock (`Date() + 86400`) guarantees every slot's endToday < now, making
    // // all unfinished slots count as expired without relying on specific wall-clock hours.
    // // Tests for snoozed-based misses use `now = Date()` with wide-window slots.

    // @Suite("HabitAndSlot — missed")
    // final class HabitAndSlotMissedTests {

    //     private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)
    //     init() { UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey) }
    //     deinit { UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey) }

    //     /// A `now` one full day ahead of the real clock — every today-anchored endToday is
    //     /// in the past relative to this, so unfinished slots are always expired.
    //     private var tomorrow: Date { Date().addingTimeInterval(86_400) }

    //     @Test("empty habits → empty")
    //     @MainActor func emptyHabits() throws {
    //         let result = HabitAndSlot.missed(habits: [], snoozedSlots: [], now: tomorrow)
    //         #expect(result.isEmpty)
    //     }

    //     @Test("habit with no slots → omitted")
    //     @MainActor func habitWithNoSlotsOmitted() throws {
    //         let container = try makeContainer()
    //         let ctx = container.mainContext
    //         let habit = makeHabit(in: ctx)
    //         let result = HabitAndSlot.missed(habits: [habit], snoozedSlots: [], now: tomorrow)
    //         #expect(result.isEmpty)
    //     }

    //     @Test("expired slot → habit appears as missed with missedCount = 1")
    //     @MainActor func expiredSlotIsMissed() throws {
    //         let container = try makeContainer()
    //         let ctx = container.mainContext
    //         let habit = makeHabit(in: ctx, slots: [makeSlot(startHour: 9, endHour: 10)])
    //         let result = HabitAndSlot.missed(habits: [habit], snoozedSlots: [], now: tomorrow)
    //         #expect(result.count == 1)
    //         #expect(result[0].habit === habit)
    //         #expect(result[0].missedCount == 1)
    //     }

    //     @Test("completed slot is not counted as missed")
    //     @MainActor func completedSlotNotMissed() throws {
    //         let container = try makeContainer()
    //         let ctx = container.mainContext
    //         let habit = makeHabit(in: ctx, slots: [makeSlot(startHour: 9, endHour: 10)])
    //         // Check in against real `now` so the psychDay matches.
    //         ctx.insert(HabitCheckIn(habit: habit, createdAt: Date()))
    //         let result = HabitAndSlot.missed(habits: [habit], snoozedSlots: [], now: tomorrow)
    //         #expect(result.isEmpty)
    //     }

    //     @Test("two expired slots for one habit → missedCount = 2")
    //     @MainActor func twoExpiredSlotsCount() throws {
    //         let container = try makeContainer()
    //         let ctx = container.mainContext
    //         let habit = makeHabit(
    //             in: ctx,
    //             slots: [
    //                 makeSlot(startHour: 7, endHour: 8),
    //                 makeSlot(startHour: 14, endHour: 15),
    //             ])
    //         let result = HabitAndSlot.missed(habits: [habit], snoozedSlots: [], now: tomorrow)
    //         #expect(result.count == 1)
    //         #expect(result[0].missedCount == 2)
    //     }

    //     @Test("snoozed slot within active window → counted as missed")
    //     @MainActor func snoozedSlotWithinWindowIsMissed() throws {
    //         let container = try makeContainer()
    //         let ctx = container.mainContext
    //         // Wide window (0-23) is still active at any test-run time, so expiry doesn't apply.
    //         // The snooze alone triggers missed.
    //         let s = makeSlot(startHour: 0, endHour: 23)
    //         let habit = makeHabit(in: ctx, slots: [s])
    //         let snooze = SnoozedSlot(habit: habit, slot: s)
    //         ctx.insert(snooze)
    //         let result = HabitAndSlot.missed(habits: [habit], snoozedSlots: [snooze], now: Date())
    //         #expect(result.count == 1)
    //         #expect(result[0].missedCount == 1)
    //     }

    //     @Test("most overdue habit sorts first")
    //     @MainActor func sortsByOverdueDurationDescending() throws {
    //         let container = try makeContainer()
    //         let ctx = container.mainContext
    //         // Habit A ended at 8am, habit B ended at 10am — A is more overdue.
    //         let habitA = makeHabit(in: ctx, title: "A", slots: [makeSlot(startHour: 7, endHour: 8)])
    //         let habitB = makeHabit(
    //             in: ctx, title: "B", slots: [makeSlot(startHour: 9, endHour: 10)])
    //         let result = HabitAndSlot.missed(
    //             habits: [habitA, habitB], snoozedSlots: [], now: tomorrow)
    //         #expect(result.count == 2)
    //         // A (overdue since 8am) has been missed longer than B (overdue since 10am).
    //         #expect(result[0].habit === habitA)
    //         #expect(result[1].habit === habitB)
    //     }

    //     @Test("overdueBy is non-negative")
    //     @MainActor func overdueByIsNonNegative() throws {
    //         let container = try makeContainer()
    //         let ctx = container.mainContext
    //         let habit = makeHabit(in: ctx, slots: [makeSlot(startHour: 9, endHour: 10)])
    //         let result = HabitAndSlot.missed(habits: [habit], snoozedSlots: [], now: tomorrow)
    //         #expect(result[0].overdueBy >= 0)
    //     }
    // }

    // MARK: - HabitAndSlot.nextTransitionDate
    //
    // With `dayStartHourOffset = 0` and a fixed past `now`, the next psychDay boundary
    // is midnight of the calendar day after `now` — a deterministic, verifiable value.
    // All slot startToday / endToday values (anchored to the real clock) exceed that
    // boundary and cannot be the minimum candidate.

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
