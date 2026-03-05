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
/// semantics HabitSlot uses for its start/end fields.
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
    let schema = Schema([Habit.self, HabitSlot.self, HabitCheckIn.self, SnoozedSlot.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

/// Creates a HabitSlot (uninserted). Pass the slot to `makeHabit(in:slots:)` so the
/// correct insertion order is always observed.
private func makeSlot(startHour: Int, endHour: Int) -> HabitSlot {
    HabitSlot(start: timeOfDay(hour: startHour), end: timeOfDay(hour: endHour))
}

/// Creates a habit and inserts it and all its slots into `ctx`.
/// Slots must be explicitly inserted — SwiftData does not cascade-insert them automatically.
@MainActor
private func makeHabit(
    in ctx: ModelContext,
    title: String = "A",
    slots: [HabitSlot] = [],
    skipCreditCount: Int = 0,
    skipCreditPeriod: Period = .daily
) -> Habit {
    let habit = Habit(
        title: title, slots: slots,
        skipCreditCount: skipCreditCount, skipCreditPeriod: skipCreditPeriod)
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

@Suite("Habit slots queries")
struct HabitSlotsQueriesTests {
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

    // MARK: - hasUnfinishedSlots

    @Suite("Habit — hasUnfinishedSlots")
    final class HabitUnfinishedTodayTests {

        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)
        init() { UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey) }
        deinit { UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey) }

        let psychDay = date(year: 2026, month: 3, day: 5)

        @Test("no check-ins → true")
        @MainActor func noCheckInsIsUnfinished() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, slots: [makeSlot(startHour: 9, endHour: 10)])
            #expect(habit.hasUnfinishedSlots(for: psychDay) == true)
        }

        @Test("partial completion → true")
        @MainActor func partialCompletionIsUnfinished() throws {
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
            #expect(habit.hasUnfinishedSlots(for: psychDay) == true)
        }

        @Test("all slots completed → false")
        @MainActor func allCompletedIsFinished() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, slots: [makeSlot(startHour: 9, endHour: 10)])
            ctx.insert(
                HabitCheckIn(habit: habit, createdAt: date(year: 2026, month: 3, day: 5, hour: 9)))
            #expect(habit.hasUnfinishedSlots(for: psychDay) == false)
        }

        @Test("no slots → false (nothing to do)")
        @MainActor func noSlotsIsFinished() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx)
            #expect(habit.hasUnfinishedSlots(for: psychDay) == false)
        }
    }

    // MARK: - firstCurrentSlot
    //
    // startToday / endToday on HabitSlot are computed against the real clock (Date()),
    // independent of the `now` parameter. To make window checks deterministic, tests
    // use wide-window slots (00:00–23:00) that are always active for any reasonable
    // test execution time.

    @Suite("Habit — firstCurrentSlot")
    final class HabitFirstCurrentSlotTests {

        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)
        init() { UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey) }
        deinit { UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey) }

        /// Spans midnight to 23:00 — always contains the current time for any sane run.
        private func fullDaySlot(startHour: Int = 0) -> HabitSlot {
            makeSlot(startHour: startHour, endHour: 23)
        }

        @Test("slot in window, no snoozed → returned")
        @MainActor func slotInWindowReturned() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, slots: [fullDaySlot()])
            #expect(habit.firstCurrentSlot(now: Date(), excluding: []) != nil)
        }

        @Test("only slot is snoozed → nil")
        @MainActor func snoozedSlotReturnsNil() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let s = fullDaySlot()
            let habit = makeHabit(in: ctx, slots: [s])
            let snooze = SnoozedSlot(habit: habit, slot: s)
            ctx.insert(snooze)
            #expect(habit.firstCurrentSlot(now: Date(), excluding: [snooze]) == nil)
        }

        @Test("first slot snoozed → second slot returned")
        @MainActor func snoozedFirstSlotReturnsSecond() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            // s1 sorts before s2 (lower start hour). Both windows span the full day.
            let s1 = fullDaySlot(startHour: 0)
            let s2 = fullDaySlot(startHour: 1)
            let habit = makeHabit(in: ctx, slots: [s1, s2])
            let snooze = SnoozedSlot(habit: habit, slot: s1)
            ctx.insert(snooze)
            let result = habit.firstCurrentSlot(now: Date(), excluding: [snooze])
            #expect(result != nil)
            #expect(result?.start == s2.start)
        }

        @Test("no remaining slots (all completed today) → nil")
        @MainActor func noRemainingSlots() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, slots: [fullDaySlot()])
            ctx.insert(HabitCheckIn(habit: habit, createdAt: Date()))
            #expect(habit.firstCurrentSlot(now: Date(), excluding: []) == nil)
        }

        @Test("empty snoozed list does not exclude anything")
        @MainActor func emptySnoozedList() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, slots: [fullDaySlot()])
            #expect(habit.firstCurrentSlot(now: Date(), excluding: []) != nil)
        }
    }

    // MARK: - firstFutureSlot
    //
    // startToday is resolved against the real clock. By passing a fixed past date as
    // `now`, any slot's startToday (which is always "today" or later) is reliably
    // greater than now, making every slot appear to be in the future.

    @Suite("Habit — firstFutureSlot")
    final class HabitFirstFutureSlotTests {

        // Any past date works here — startToday is always "real today", which is after this.
        let now = date(year: 2026, month: 3, day: 5, hour: 10)

        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)
        init() { UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey) }
        deinit { UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey) }

        @Test("slot in the future → returned")
        @MainActor func futureSlotReturned() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, slots: [makeSlot(startHour: 14, endHour: 15)])
            #expect(habit.firstFutureSlot(now: now) != nil)
        }

        @Test("earliest future slot returned when multiple slots exist")
        @MainActor func earliestFutureSlotReturned() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let morning = makeSlot(startHour: 7, endHour: 8)
            let afternoon = makeSlot(startHour: 14, endHour: 15)
            let habit = makeHabit(in: ctx, slots: [afternoon, morning])
            let result = habit.firstFutureSlot(now: now)
            // Morning (hour 7) sorts before afternoon (hour 14) and should be returned.
            #expect(result?.start == morning.start)
        }

        @Test("all slots completed today → nil")
        @MainActor func allCompletedReturnsNil() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx, slots: [makeSlot(startHour: 9, endHour: 10)])
            ctx.insert(HabitCheckIn(habit: habit, createdAt: now))
            #expect(habit.firstFutureSlot(now: now) == nil)
        }

        @Test("no slots → nil")
        @MainActor func noSlotsReturnsNil() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let habit = makeHabit(in: ctx)
            #expect(habit.firstFutureSlot(now: now) == nil)
        }

        @Test("completed slot is excluded from future candidates")
        @MainActor func completedSlotExcluded() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let morning = makeSlot(startHour: 7, endHour: 8)
            let afternoon = makeSlot(startHour: 14, endHour: 15)
            let habit = makeHabit(in: ctx, slots: [morning, afternoon])
            // Complete the first occurrence (morning slot dropped from remainingSlots).
            ctx.insert(HabitCheckIn(habit: habit, createdAt: now))
            // firstFutureSlot should now return afternoon, not morning.
            let result = habit.firstFutureSlot(now: now)
            #expect(result?.start == afternoon.start)
        }
    }
}
