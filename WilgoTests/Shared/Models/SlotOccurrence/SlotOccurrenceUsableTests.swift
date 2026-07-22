import Foundation
import SwiftData
import Testing
@testable import Wilgo

/// `SlotOccurrence.isUsable(checkIns:)` = not snoozed AND not saturated. Verifies the
/// composition: each suppressor alone makes it unusable, and a clean occurrence is usable.
extension SlotOccurrenceSuite {
@Suite(.serialized)
final class SlotOccurrenceUsableTests {
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

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y
        c.month = m
        c.day = d
        c.hour = h
        c.minute = min
        c.second = 0
        return Calendar.current.date(from: c)!
    }

    @MainActor
    private func makeCommitmentAndSlot(cap: Int?, in ctx: ModelContext) -> (Commitment, Slot) {
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        slot.maxCheckIns = cap
        let commitment = Commitment(
            title: "T",
            cycle: Cycle(kind: .daily, referencePsychDay: date(2026, 1, 1)),
            slots: [slot],
            target: Target(count: 5)
        )
        ctx.insert(commitment)
        ctx.insert(slot)
        return (commitment, slot)
    }

    // MARK: - Tests

    @Test("clean occurrence (not snoozed, not saturated) → usable")
    @MainActor func clean_usable() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let (_, slot) = makeCommitmentAndSlot(cap: nil, in: ctx)

        let occ = try #require(slot.occurrence(on: date(2026, 3, 5)))
        #expect(occ.isUsable(checkIns: []) == true)
    }

    @Test("snoozed occurrence → not usable")
    @MainActor func snoozed_notUsable() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let (_, slot) = makeCommitmentAndSlot(cap: nil, in: ctx)

        let snooze = SlotSnooze(
            slot: slot, psychDay: date(2026, 3, 5), snoozedAt: date(2026, 3, 5, 10))
        ctx.insert(snooze)

        let occ = try #require(slot.occurrence(on: date(2026, 3, 5)))
        #expect(occ.isUsable(checkIns: []) == false)
    }

    @Test("saturated occurrence → not usable")
    @MainActor func saturated_notUsable() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let (commitment, slot) = makeCommitmentAndSlot(cap: 1, in: ctx)

        let ci = CheckIn(commitment: commitment, createdAt: date(2026, 3, 5, 10))
        ctx.insert(ci)

        let occ = try #require(slot.occurrence(on: date(2026, 3, 5)))
        #expect(occ.isUsable(checkIns: [ci]) == false)
    }
}
}
