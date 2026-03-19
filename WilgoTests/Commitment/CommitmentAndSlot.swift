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
    let schema = Schema([Commitment.self, Slot.self, CheckIn.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

private func makeSlot(startHour: Int, endHour: Int) -> Slot {
    Slot(start: timeOfDay(hour: startHour), end: timeOfDay(hour: endHour))
}

@MainActor
private func makeCommitment(
    in ctx: ModelContext,
    title: String = "A",
    slots: [Slot] = [],
    goalCountPerDay: Int = 2
) -> Commitment {
    let commitment = Commitment(
        title: title,
        slots: slots,
        skipBudget: SkipBudget(cycle: .daily, countPerCycle: 0),
        goalCountPerDay: goalCountPerDay)
    ctx.insert(commitment)
    for slot in slots { ctx.insert(slot) }
    return commitment
}

@Suite("CommitmentAndSlot tests", .serialized)  // seems that parallelly running the test create some mysterious bug
struct CommitmentAndSlotTests {
    // MARK: - CommitmentAndSlot.current
    @Suite("CommitmentAndSlot — current")
    final class CommitmentAndSlotCurrentTests {

        // Frozen instant used as the injectable clock for the entire suite.
        // All slot startToday/endToday values are anchored to this date, and
        // noonNow (passed as `now`) falls within the wide window (00:00–23:00).
        private static let frozenNoon = date(year: 2025, month: 6, day: 15, hour: 12)

        private let savedNow = Time.now
        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)

        init() {
            UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey)
            Time.now = { CommitmentAndSlotCurrentTests.frozenNoon }
        }

        deinit {
            let savedNow = savedNow
            let savedOffset = savedOffset
            UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey)
            Time.now = savedNow
        }

        private func wideSlot(endHour: Int = 23) -> Slot {
            makeSlot(startHour: 0, endHour: endHour)
        }

        @Test("empty commitments → empty")
        @MainActor func emptyCommitments() throws {
            let result = CommitmentAndSlot.current(commitments: [])
            #expect(result.isEmpty)
        }

        @Test("commitments whose daily goal has been met → empty")
        @MainActor func commitmentsWithMetDailyGoal() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(in: ctx, slots: [wideSlot()])
            ctx.insert(
                CheckIn(commitment: commitment, createdAt: Time.now()))  // met daily goal
            let result = CommitmentAndSlot.current(commitments: [commitment])
            #expect(result.isEmpty)
        }

        @Test("overlap with now → commitment included")
        @MainActor func overlapWithNowIncluded() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(in: ctx, slots: [wideSlot()])
            let result = CommitmentAndSlot.current(commitments: [commitment])
            #expect(result.count == 1)
            #expect(result[0].0 === commitment)  // commitment is included
        }

        @Test("more urgent slot (less remaining fraction) sorts first")
        @MainActor func sortsByRemainingFraction() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitmentA = makeCommitment(in: ctx, title: "A", slots: [wideSlot(endHour: 23)])
            let commitmentB = makeCommitment(in: ctx, title: "B", slots: [wideSlot(endHour: 22)])
            let result = CommitmentAndSlot.current(commitments: [commitmentA, commitmentB])
            #expect(result.count == 2)
            #expect(result[0].0 === commitmentB)  // B (end=22) is more urgent
            #expect(result[1].0 === commitmentA)
        }
    }

    // MARK: - CommitmentAndSlot.upcoming
    @Suite("CommitmentAndSlot — upcoming")
    final class CommitmentAndSlotUpcomingTests {

        // // Frozen instant used as the injectable clock for the entire suite.
        // private static let fakeNow = date(year: 2025, month: 6, day: 15, hour: 0)

        // private let savedNow = Time.now
        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)

        init() {
            UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey)
            // Time.now = { return CommitmentAndSlotUpcomingTests.fakeNow }
        }

        deinit {
            // let savedNow = savedNow
            let savedOffset = savedOffset
            UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey)
            // Time.now = savedNow
        }

        @Test("empty commitments → empty")
        @MainActor func emptyCommitments() throws {
            let result = CommitmentAndSlot.upcoming(
                commitments: [], after: date(year: 2000, month: 1, day: 1, hour: 0))
            #expect(result.isEmpty)
        }

        @Test("commitment with no slots → omitted")
        @MainActor func commitmentWithNoSlotsOmitted() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(in: ctx)
            let result = CommitmentAndSlot.upcoming(
                commitments: [commitment], after: date(year: 2000, month: 1, day: 1, hour: 0))
            #expect(result.isEmpty)
        }

        @Test("commitment with a future slot → included")
        @MainActor func futureSlotIncluded() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(in: ctx, slots: [makeSlot(startHour: 14, endHour: 15)])  // afternoon is later than noon.
            let result = CommitmentAndSlot.upcoming(
                commitments: [commitment], after: date(year: 2000, month: 1, day: 1, hour: 0))
            #expect(result.count == 1)
            #expect(result[0].0 === commitment)
        }

        @Test("commitment with met daily goal → commitment omitted")
        @MainActor func commitmentWithMetDailyGoalOmitted() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(
                in: ctx, slots: [makeSlot(startHour: 9, endHour: 10)], goalCountPerDay: 1)
            ctx.insert(
                CheckIn(
                    commitment: commitment, createdAt: date(year: 2000, month: 1, day: 1, hour: 0)))
            let result = CommitmentAndSlot.upcoming(
                commitments: [commitment], after: date(year: 2000, month: 1, day: 1, hour: 0))
            #expect(result.isEmpty)
        }

        @Test("multiple commitments: sorted by ascending slot start time")
        @MainActor func sortedBySlotStartTime() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            // Insert afternoon-first commitment to prove we're not relying on insertion order.
            let commitmentLate = makeCommitment(
                in: ctx, title: "Late", slots: [makeSlot(startHour: 15, endHour: 16)])
            let commitmentEarly = makeCommitment(
                in: ctx, title: "Early", slots: [makeSlot(startHour: 13, endHour: 14)])
            let result = CommitmentAndSlot.upcoming(
                commitments: [commitmentLate, commitmentEarly],
                after: date(year: 2000, month: 1, day: 1, hour: 0))
            #expect(result.count == 2)

            #expect(result[0] == (commitmentEarly, commitmentEarly.slots[0]))
            #expect(result[1] == (commitmentLate, commitmentLate.slots[0]))
        }

        @Test("only first future slot per commitment is returned")
        @MainActor func onlyFirstFutureSlot() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let morning = makeSlot(startHour: 7, endHour: 8)
            let afternoon = makeSlot(startHour: 14, endHour: 15)
            let commitment = makeCommitment(in: ctx, slots: [morning, afternoon])
            let result = CommitmentAndSlot.upcoming(
                commitments: [commitment], after: date(year: 2000, month: 1, day: 1, hour: 0))
            #expect(result.count == 1)
            #expect(result[0] == (commitment, morning))
        }
    }

    @Suite("CommitmentAndSlot — nextTransitionDate")
    final class CommitmentAndSlotNextTransitionDateTests {

        // Frozen instant used as the injectable clock for the entire suite.
        private static let fakeNow = date(year: 2025, month: 6, day: 15, hour: 6)
        private static let nextPsychDayStart = date(year: 2025, month: 6, day: 16, hour: 0)

        private let savedNow = Time.now
        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)

        init() {
            UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey)
            Time.now = { return CommitmentAndSlotNextTransitionDateTests.fakeNow }
        }

        deinit {
            let savedNow = savedNow
            let savedOffset = savedOffset
            UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey)
            Time.now = savedNow
        }

        @Test("empty commitments → returns the next psychDay boundary")
        @MainActor func emptyCommitmentsReturnsPsychDayBoundary() throws {
            print("111Time.now() = \(Time.now())")
            let result = CommitmentAndSlot.nextTransitionDate(commitments: [])
            #expect(result == CommitmentAndSlotNextTransitionDateTests.nextPsychDayStart)
        }

        @Test("simple one slot case")
        @MainActor func oneSlotCase() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(in: ctx, slots: [makeSlot(startHour: 9, endHour: 10)])
            let result = CommitmentAndSlot.nextTransitionDate(commitments: [commitment])
            #expect(result != nil)
            #expect(result! == date(year: 2025, month: 6, day: 15, hour: 9))
        }

        @Test("start is already passed now")
        @MainActor func startIsAlreadyPassedNow() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(in: ctx, slots: [makeSlot(startHour: 4, endHour: 10)])
            let result = CommitmentAndSlot.nextTransitionDate(commitments: [commitment])
            #expect(result != nil)
            #expect(result! == date(year: 2025, month: 6, day: 15, hour: 10))
        }

        @Test("multiple slots case")
        @MainActor func multipleSlotsCase() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(
                in: ctx,
                slots: [makeSlot(startHour: 4, endHour: 10), makeSlot(startHour: 8, endHour: 11)])
            let result = CommitmentAndSlot.nextTransitionDate(commitments: [commitment])
            #expect(result != nil)
            #expect(result! == date(year: 2025, month: 6, day: 15, hour: 8))
        }
    }
}
