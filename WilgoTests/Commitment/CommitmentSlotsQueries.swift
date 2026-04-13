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
    let schema = Schema([Commitment.self, Slot.self, CheckIn.self, SlotSnooze.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

/// Creates a Slot (uninserted). Pass the slot to `makeCommitment(in:slots:)` so the
/// correct insertion order is always observed.
private func makeSlot(startHour: Int, endHour: Int) -> Slot {
    Slot(start: timeOfDay(hour: startHour), end: timeOfDay(hour: endHour))
}

/// Creates a commitment and inserts it and all its slots into `ctx`.
/// Slots must be explicitly inserted — SwiftData does not cascade-insert them automatically.
@MainActor
private func makeCommitment(
    in ctx: ModelContext,
    title: String = "A",
    goalCountPerDay: Int = 1,
    slots: [Slot] = []
) -> Commitment {
    let anchor = date(year: 2026, month: 1, day: 1)
    let dailyCycle = Cycle(kind: .daily, referencePsychDay: anchor)
    let commitment = Commitment(
        title: title,
        slots: slots,
        target: QuantifiedCycle(cycle: dailyCycle, count: goalCountPerDay),
    )
    ctx.insert(commitment)
    for slot in slots { ctx.insert(slot) }
    return commitment
}

// MARK: - completedCount

@Suite("Commitment slots queries", .serialized)
struct SlotsQueriesTests {
    // MARK: - firstCurrentSlot

    @Suite("Commitment — firstCurrentSlot")
    final class CommitmentFirstCurrentSlotTests {
        // Frozen instant used as the injectable clock for the entire suite.
        private static let fakeNow = date(year: 2000, month: 1, day: 1, hour: 12)

        private let savedNow = Time.now

        init() {
            Time.now = { return CommitmentFirstCurrentSlotTests.fakeNow }
        }

        deinit {
            let savedNow = savedNow
            Time.now = savedNow
        }

        private func wideSlot(startHour: Int = 0) -> Slot {
            makeSlot(startHour: startHour, endHour: 23)
        }

        @Test("slot in window, no exclude → returned")
        @MainActor func slotInWindowReturned() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(in: ctx, slots: [wideSlot()])
            #expect(
                commitment.firstCurrentSlot(
                    now: Time.now(), excluding: []) != nil)
        }

        @Test("only slot is excluded → nil")
        @MainActor func excludedSlotReturnsNil() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let s = wideSlot()
            let commitment = makeCommitment(in: ctx, slots: [s])
            #expect(
                commitment.firstCurrentSlot(
                    now: Time.now(), excluding: [s]) == nil)
        }

        @Test("first slot excluded → second slot returned")
        @MainActor func excludedFirstSlotReturnsSecond() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            // s1 sorts before s2 (lower start hour). Both windows span wide.
            let s1 = wideSlot(startHour: 0)
            let s2 = wideSlot(startHour: 1)
            let commitment = makeCommitment(in: ctx, slots: [s1, s2])
            let result = commitment.firstCurrentSlot(
                now: Time.now(), excluding: [s1])
            #expect(result != nil)
            #expect(result?.start == s2.start)
        }

        @Test("slot on the same day, slot in window → returned")
        @MainActor func slotOnSameDayInWindow() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let s1 = makeSlot(startHour: 11, endHour: 13)
            let commitment = makeCommitment(in: ctx, slots: [s1])
            let result = commitment.firstCurrentSlot(
                now: Time.now(), excluding: [])
            #expect(result != nil)
            #expect(result == s1)
        }

        @Test("slot not in window → nil")
        @MainActor func slotNotInWindow() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let s1 = makeSlot(startHour: 9, endHour: 10)
            let commitment = makeCommitment(in: ctx, slots: [s1])
            let result = commitment.firstCurrentSlot(
                now: Time.now(), excluding: [])
            #expect(result == nil)
        }

        @Test("cross-midnight slot in window → returned")
        @MainActor func crossMidnightSlotInWindow() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let s1 = makeSlot(startHour: 23, endHour: 13)
            let commitment = makeCommitment(in: ctx, slots: [s1])
            let result = commitment.firstCurrentSlot(
                now: Time.now(), excluding: [])
            #expect(result != nil)
            #expect(result == s1)
        }

        @Test("cross-midnight slot not in window → nil")
        @MainActor func crossMidnightSlotNotInWindow() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let s1 = makeSlot(startHour: 23, endHour: 11)
            let commitment = makeCommitment(in: ctx, slots: [s1])
            let result = commitment.firstCurrentSlot(
                now: Time.now(), excluding: [])
            #expect(result == nil)
        }
    }

    // MARK: - firstSlotAfter

    @Suite("Commitment — firstSlotAfter")
    final class CommitmentFirstSlotAfterTests {
        @Test("slot in the future → returned")
        @MainActor func futureSlotReturned() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let s1 = makeSlot(startHour: 14, endHour: 15)
            let commitment = makeCommitment(in: ctx, slots: [s1])
            let result = commitment.firstSlotAfter(
                time: date(year: 2000, month: 1, day: 1, hour: 12))
            #expect(result == s1)
        }

        @Test("earliest future slot returned when multiple slots exist")
        @MainActor func earliestFutureSlotReturned() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let s1 = makeSlot(startHour: 13, endHour: 14)
            let s2 = makeSlot(startHour: 15, endHour: 16)
            let commitment = makeCommitment(in: ctx, slots: [s2, s1])
            let result = commitment.firstSlotAfter(
                time: date(year: 2000, month: 1, day: 1, hour: 12))
            #expect(result == s1)
        }

        @Test("check-ins do not affect firstSlotAfter")
        @MainActor func checkInsDoNotMatter() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let s1 = makeSlot(startHour: 15, endHour: 16)
            let commitment = makeCommitment(in: ctx, slots: [s1])
            ctx.insert(
                CheckIn(
                    commitment: commitment, createdAt: date(year: 2000, month: 1, day: 1, hour: 12))
            )
            let result = commitment.firstSlotAfter(
                time: date(year: 2000, month: 1, day: 1, hour: 12))
            #expect(result == s1)
        }

        @Test("no slots → nil")
        @MainActor func noSlotsReturnsNil() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(in: ctx)
            let result = commitment.firstSlotAfter(
                time: date(year: 2000, month: 1, day: 1, hour: 12))
            #expect(result == nil)
        }

        @Test("past slot is excluded")
        @MainActor func pastSlotExcluded() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let morning = makeSlot(startHour: 7, endHour: 8)
            let afternoon = makeSlot(startHour: 14, endHour: 15)
            let commitment = makeCommitment(in: ctx, slots: [morning, afternoon])
            let result = commitment.firstSlotAfter(
                time: date(year: 2000, month: 1, day: 1, hour: 12))
            #expect(result == afternoon)
        }
    }
}
