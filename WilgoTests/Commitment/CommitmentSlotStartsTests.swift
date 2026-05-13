import Foundation
import SwiftData
import Testing

@testable import Wilgo

@Suite("Commitment - SlotStarts", .serialized)
final class CommitmentUpcomingSlotStartsTests {

    // MARK: - Helpers

    private func tod(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2000
        c.month = 1
        c.day = 1
        c.hour = hour
        c.minute = minute
        c.second = 0
        return Calendar.current.date(from: c)!
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        c.minute = minute
        c.second = 0
        return Calendar.current.date(from: c)!
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, SlotSnooze.self, Tag.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    @MainActor
    private func makeCommitment(
        slots slotDefs: [(start: Int, end: Int, maxCheckIns: Int?)],
        targetCount: Int = 3,
        targetMode: TargetMode = .on,
        cycleKind: CycleKind = .daily,
        in ctx: ModelContext
    ) -> Commitment {
        let anchor = date(year: 2026, month: 1, day: 1)
        let slots = slotDefs.map {
            Slot(start: tod(hour: $0.start), end: tod(hour: $0.end), maxCheckIns: $0.maxCheckIns)
        }
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: cycleKind, referencePsychDay: anchor),
            slots: slots,
            target: Target(count: targetCount, mode: targetMode)
        )
        ctx.insert(c)
        slots.forEach { ctx.insert($0) }
        return c
    }

    @MainActor
    private func addCheckIn(to c: Commitment, at date: Date, in ctx: ModelContext) {
        let checkIn = CheckIn(commitment: c, createdAt: date)
        ctx.insert(checkIn)
        c.checkIns.append(checkIn)
    }

    @MainActor
    private func addSnooze(to slot: Slot, at date: Date, in ctx: ModelContext) {
        SlotSnooze.create(slot: slot, at: date, in: ctx)
    }

    // MARK: - Tests

    @Test("start after from is returned")
    @MainActor func futureSlot_returned() throws {
        let container = try makeContainer()
        let c = makeCommitment(slots: [(9, 11, nil)], in: container.mainContext)
        let from = date(year: 2026, month: 3, day: 5, hour: 7)
        let to = date(year: 2026, month: 3, day: 6)

        let starts = c.slotStarts(from: from, to: to)

        #expect(starts.count == 1)
        #expect(starts.first == date(year: 2026, month: 3, day: 5, hour: 9))
    }

    @Test("slot start before `from` is excluded")
    @MainActor func pastSlot_excluded() throws {
        let container = try makeContainer()
        let c = makeCommitment(slots: [(9, 11, nil)], in: container.mainContext)
        let from = date(year: 2026, month: 3, day: 5, hour: 10)  // already inside slot
        let to = date(year: 2026, month: 3, day: 6)

        let starts = c.slotStarts(from: from, to: to)

        // start (9am) is before from (10am) → excluded
        #expect(starts.isEmpty)
    }

    @Test("multiple slots per day both returned")
    @MainActor func multipleSlotsPerDay_allReturned() throws {
        let container = try makeContainer()
        let c = makeCommitment(slots: [(9, 11, nil), (18, 20, nil)], in: container.mainContext)
        let from = date(year: 2026, month: 3, day: 5, hour: 7)
        let to = date(year: 2026, month: 3, day: 6)

        let starts = c.slotStarts(from: from, to: to)

        #expect(starts.count == 2)
        #expect(starts.contains(date(year: 2026, month: 3, day: 5, hour: 9)))
        #expect(starts.contains(date(year: 2026, month: 3, day: 5, hour: 18)))
    }

    @Test("slots across multiple days all returned")
    @MainActor func multiDay_allReturned() throws {
        let container = try makeContainer()
        let c = makeCommitment(slots: [(9, 11, nil)], in: container.mainContext)
        let from = date(year: 2026, month: 3, day: 5, hour: 7)
        let to = date(year: 2026, month: 3, day: 8)

        let starts = c.slotStarts(from: from, to: to)

        #expect(starts.count == 3)
        #expect(starts.contains(date(year: 2026, month: 3, day: 5, hour: 9)))
        #expect(starts.contains(date(year: 2026, month: 3, day: 6, hour: 9)))
        #expect(starts.contains(date(year: 2026, month: 3, day: 7, hour: 9)))
    }

    @Test("slot after to is excluded")
    @MainActor func beyondto_excluded() throws {
        let container = try makeContainer()
        let c = makeCommitment(slots: [(9, 11, nil)], in: container.mainContext)
        let from = date(year: 2026, month: 3, day: 5, hour: 7)
        let to = date(year: 2026, month: 3, day: 5, hour: 8)  // before slot at 9am

        let starts = c.slotStarts(from: from, to: to)

        #expect(starts.isEmpty)
    }

    @Test("saturated slot is excluded")
    @MainActor func saturatedSlot_excluded() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11, 1)], targetCount: 3, in: ctx)  // maxCheckIns: 1
        let from = date(year: 2026, month: 3, day: 5, hour: 7)
        // Check-in must be within the slot window [9am, 11am) to count as saturating
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 9), in: ctx)
        let to = date(year: 2026, month: 3, day: 6)

        let starts = c.slotStarts(from: from, to: to)

        #expect(starts.isEmpty)
    }

    @Test("snoozed slot is excluded")
    @MainActor func snoozedSlot_excluded() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11, nil)], in: ctx)
        let slot = try #require(c.slots.first)
        let from = date(year: 2026, month: 3, day: 5, hour: 7)
        // Snooze must be created at a time within the slot window for SlotSnooze.create to succeed
        addSnooze(to: slot, at: date(year: 2026, month: 3, day: 5, hour: 9), in: ctx)
        let to = date(year: 2026, month: 3, day: 6)

        let starts = c.slotStarts(from: from, to: to)

        #expect(starts.isEmpty)
    }
}
