import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite(.serialized)
final class CommitmentSlotOccurrencesTests {
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
        slot.snooze(at: date, in: ctx)
    }

    // MARK: - Tests

    @Test("merges occurrences across all of the commitment's slots")
    @MainActor func mergesAcrossSlots() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(slots: [(9, 11, nil), (18, 20, nil)], in: container.mainContext)
        let from = date(year: 2026, month: 3, day: 5, hour: 7)
        let to = date(year: 2026, month: 3, day: 6)
        // One occurrence from each slot on Mar 5 — build them directly and compare firings.
        let morning = try #require(c.slots[0].occurrence(on: date(year: 2026, month: 3, day: 5)))
        let evening = try #require(c.slots[1].occurrence(on: date(year: 2026, month: 3, day: 5)))

        let occs = c.slotOccurrences(from: from, until: to, softFrom: false)

        // Sorted chronologically (SlotOccurrence: Comparable), so morning precedes evening.
        #expect(occs == [morning, evening])
    }

    @Test("merged occurrences are sorted chronologically across slots and days")
    @MainActor func mergedResultIsSorted() throws {
        let container = try makeTestContainer()
        // Two slots whose per-slot enumeration interleaves once merged: an 18–20 evening slot and a
        // 9–11 morning slot. `flatMap` visits them slot-by-slot (all evenings, then all mornings, or
        // vice versa), so only the final sort produces chronological order.
        let c = makeCommitment(slots: [(18, 20, nil), (9, 11, nil)], in: container.mainContext)
        let from = date(year: 2026, month: 3, day: 5, hour: 7)
        let to = date(year: 2026, month: 3, day: 7)  // two days: Mar 5, 6

        let occs = c.slotOccurrences(from: from, until: to, softFrom: false)

        #expect(occs.map(\.start) == occs.map(\.start).sorted())
        #expect(
            occs.map(\.start) == [
                date(year: 2026, month: 3, day: 5, hour: 9),
                date(year: 2026, month: 3, day: 5, hour: 18),
                date(year: 2026, month: 3, day: 6, hour: 9),
                date(year: 2026, month: 3, day: 6, hour: 18),
            ])
    }

    @Test("onlyUsable gates unusable firings: filtered out when true, kept when false")
    @MainActor func onlyUsable_gatesUnusableFirings() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // maxCheckIns: 1 with a check-in inside the window makes the occurrence saturated →
        // unusable. (Whether unusability comes from saturation or snooze is SlotOccurrence's
        // concern; here we only assert the commitment applies the `isUsable` gate.)
        let c = makeCommitment(slots: [(9, 11, 1)], targetCount: 3, in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 9), in: ctx)
        let from = date(year: 2026, month: 3, day: 5, hour: 7)
        let to = date(year: 2026, month: 3, day: 6)
        let occ = try #require(c.slots[0].occurrence(on: date(year: 2026, month: 3, day: 5)))

        // Precondition: the firing really is unusable.
        #expect(!occ.isUsable(checkIns: c.checkIns))

        // Default (onlyUsable: true) filters it out; onlyUsable: false keeps it.
        #expect(c.slotOccurrences(from: from, until: to, softFrom: false).isEmpty)
        #expect(
            c.slotOccurrences(from: from, until: to, softFrom: false, onlyUsable: false) == [occ])
    }
}
