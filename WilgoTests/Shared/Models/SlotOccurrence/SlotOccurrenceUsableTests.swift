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
    @MainActor
    private func makeCommitmentAndSlot(cap: Int?, in ctx: ModelContext) -> (Commitment, Slot) {
        let slot = Slot(start: timeOfDay(hour: 9), end: timeOfDay(hour: 11))
        slot.maxCheckIns = cap
        let commitment = Commitment(
            title: "T",
            cycle: Cycle(kind: .daily, referencePsychDay: testDate(year: 2026, month: 1, day: 1)),
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

        let occ = try #require(slot.occurrence(on: testDate(year: 2026, month: 3, day: 5)))
        #expect(occ.isUsable(checkIns: []) == true)
    }

    @Test("snoozed occurrence → not usable")
    @MainActor func snoozed_notUsable() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let (_, slot) = makeCommitmentAndSlot(cap: nil, in: ctx)

        let snooze = SlotSnooze(
            slot: slot, psychDay: testDate(year: 2026, month: 3, day: 5), snoozedAt: testDate(year: 2026, month: 3, day: 5, hour: 10))
        ctx.insert(snooze)

        let occ = try #require(slot.occurrence(on: testDate(year: 2026, month: 3, day: 5)))
        #expect(occ.isUsable(checkIns: []) == false)
    }

    @Test("saturated occurrence → not usable")
    @MainActor func saturated_notUsable() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let (commitment, slot) = makeCommitmentAndSlot(cap: 1, in: ctx)

        let ci = CheckIn(commitment: commitment, createdAt: testDate(year: 2026, month: 3, day: 5, hour: 10))
        ctx.insert(ci)

        let occ = try #require(slot.occurrence(on: testDate(year: 2026, month: 3, day: 5)))
        #expect(occ.isUsable(checkIns: [ci]) == false)
    }
}
}
