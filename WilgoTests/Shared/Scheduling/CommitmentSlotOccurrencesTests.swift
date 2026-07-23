import Foundation
import SwiftData
import Testing
@testable import Wilgo

extension SchedulingSuite {
@Suite(.serialized)
final class CommitmentSlotOccurrencesTests {
    // MARK: - Helpers
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
        let c = makeCommitment(in: container.mainContext, slots: [makeSlot(startHour: 9, endHour: 11), makeSlot(startHour: 18, endHour: 20)], targetCount: 3)
        let from = testDate(year: 2026, month: 3, day: 5, hour: 7)
        let to = testDate(year: 2026, month: 3, day: 6)
        // One occurrence from each slot on Mar 5 — build them directly and compare firings.
        let morning = try #require(c.slots[0].occurrence(on: testDate(year: 2026, month: 3, day: 5)))
        let evening = try #require(c.slots[1].occurrence(on: testDate(year: 2026, month: 3, day: 5)))

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
        let c = makeCommitment(in: container.mainContext, slots: [makeSlot(startHour: 18, endHour: 20), makeSlot(startHour: 9, endHour: 11)], targetCount: 3)
        let from = testDate(year: 2026, month: 3, day: 5, hour: 7)
        let to = testDate(year: 2026, month: 3, day: 7)  // two days: Mar 5, 6

        let occs = c.slotOccurrences(from: from, until: to, softFrom: false)

        #expect(occs.map(\.start) == occs.map(\.start).sorted())
        #expect(
            occs.map(\.start) == [
                testDate(year: 2026, month: 3, day: 5, hour: 9),
                testDate(year: 2026, month: 3, day: 5, hour: 18),
                testDate(year: 2026, month: 3, day: 6, hour: 9),
                testDate(year: 2026, month: 3, day: 6, hour: 18),
            ])
    }

    @Test("onlyUsable gates unusable firings: filtered out when true, kept when false")
    @MainActor func onlyUsable_gatesUnusableFirings() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // maxCheckIns: 1 with a check-in inside the window makes the occurrence saturated →
        // unusable. (Whether unusability comes from saturation or snooze is SlotOccurrence's
        // concern; here we only assert the commitment applies the `isUsable` gate.)
        let c = makeCommitment(in: ctx, slots: [makeSlot(startHour: 9, endHour: 11, maxCheckIns: 1)], targetCount: 3)
        addCheckIn(to: c, at: testDate(year: 2026, month: 3, day: 5, hour: 9), in: ctx)
        let from = testDate(year: 2026, month: 3, day: 5, hour: 7)
        let to = testDate(year: 2026, month: 3, day: 6)
        let occ = try #require(c.slots[0].occurrence(on: testDate(year: 2026, month: 3, day: 5)))

        // Precondition: the firing really is unusable.
        #expect(!occ.isUsable(checkIns: c.checkIns))

        // Default (onlyUsable: true) filters it out; onlyUsable: false keeps it.
        #expect(c.slotOccurrences(from: from, until: to, softFrom: false).isEmpty)
        #expect(
            c.slotOccurrences(from: from, until: to, softFrom: false, onlyUsable: false) == [occ])
    }
}
}
