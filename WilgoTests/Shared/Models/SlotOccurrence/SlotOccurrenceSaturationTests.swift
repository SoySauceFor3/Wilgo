import Foundation
import SwiftData
import Testing
@testable import Wilgo

/// Saturation as a property of a concrete `SlotOccurrence` (parameter-free: the occurrence
/// already carries its slot + window). Replaces the time-parameterized `Slot.isSaturated(at:)`.
extension SlotOccurrenceSuite {
@Suite(.serialized)
final class SlotOccurrenceSaturationTests {
    // MARK: - Helpers
    @MainActor
    private func makeCommitmentAndSlot(
        cap: Int?,
        start: Int = 9, end: Int = 11,
        in ctx: ModelContext
    ) -> (Commitment, Slot) {
        let slot = Slot(start: timeOfDay(hour: start), end: timeOfDay(hour: end))
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

    // MARK: - nil cap → never saturated

    @Test("maxCheckIns nil → occurrence not saturated regardless of check-ins")
    @MainActor func nilCap_neverSaturated() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let (commitment, slot) = makeCommitmentAndSlot(cap: nil, in: ctx)

        let ci = CheckIn(commitment: commitment, createdAt: testDate(year: 2026, month: 3, day: 5, hour: 10))
        ctx.insert(ci)

        let occ = try #require(slot.occurrence(on: testDate(year: 2026, month: 3, day: 5)))
        #expect(occ.isSaturated(checkIns: [ci]) == false)
    }

    // MARK: - check-ins outside the occurrence window are not counted

    @Test("check-ins outside this occurrence's window do not count toward saturation")
    @MainActor func outOfWindowCheckIns_notCounted() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // cap=1: a single in-window check-in would saturate. We provide only OUT-of-window ones.
        let (commitment, slot) = makeCommitmentAndSlot(cap: 1, start: 9, end: 11, in: ctx)

        let before = CheckIn(commitment: commitment, createdAt: testDate(year: 2026, month: 3, day: 5, hour: 8, minute: 59))  // before start
        let atEnd = CheckIn(commitment: commitment, createdAt: testDate(year: 2026, month: 3, day: 5, hour: 11))  // == end (exclusive)
        let after = CheckIn(commitment: commitment, createdAt: testDate(year: 2026, month: 3, day: 5, hour: 12))  // after end
        let yesterday = CheckIn(commitment: commitment, createdAt: testDate(year: 2026, month: 3, day: 4, hour: 10))  // other day
        [before, atEnd, after, yesterday].forEach { ctx.insert($0) }

        let occ = try #require(slot.occurrence(on: testDate(year: 2026, month: 3, day: 5)))
        #expect(occ.isSaturated(checkIns: [before, atEnd, after, yesterday]) == false)
    }

    // MARK: - the count math is correct (below / at / above cap)

    @Test("saturation math: saturated only when in-window count >= cap")
    @MainActor func countMath_belowAtAboveCap() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let (commitment, slot) = makeCommitmentAndSlot(cap: 2, start: 9, end: 11, in: ctx)

        let inWindow1 = CheckIn(commitment: commitment, createdAt: testDate(year: 2026, month: 3, day: 5, hour: 9, minute: 30))
        let inWindow2 = CheckIn(commitment: commitment, createdAt: testDate(year: 2026, month: 3, day: 5, hour: 10, minute: 0))
        let inWindow3 = CheckIn(commitment: commitment, createdAt: testDate(year: 2026, month: 3, day: 5, hour: 10, minute: 30))
        let outside = CheckIn(commitment: commitment, createdAt: testDate(year: 2026, month: 3, day: 5, hour: 12))  // not counted
        [inWindow1, inWindow2, inWindow3, outside].forEach { ctx.insert($0) }

        let occ = try #require(slot.occurrence(on: testDate(year: 2026, month: 3, day: 5)))

        // 1 in-window (< 2) → not saturated; the outside check-in must not push it over.
        #expect(occ.isSaturated(checkIns: [inWindow1, outside]) == false)
        // exactly 2 in-window (== cap) → saturated.
        #expect(occ.isSaturated(checkIns: [inWindow1, inWindow2, outside]) == true)
        // 3 in-window (> cap) → still saturated.
        #expect(occ.isSaturated(checkIns: [inWindow1, inWindow2, inWindow3]) == true)
    }

    // MARK: - cross-midnight window counts its post-midnight tail

    @Test("cross-midnight occurrence: a post-midnight check-in inside the window counts")
    @MainActor func crossMidnight_postMidnightCheckInCounts() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // Slot 11pm–1am, cap=1. The Dec 31 occurrence's window is [Dec31 23:00, Jan1 01:00).
        let (commitment, slot) = makeCommitmentAndSlot(cap: 1, start: 23, end: 1, in: ctx)

        // Check-in at 12:30am Jan 1 — past midnight, but inside the Dec 31 occurrence's window.
        let postMidnight = CheckIn(commitment: commitment, createdAt: testDate(year: 2026, month: 1, day: 1, hour: 0, minute: 30))
        ctx.insert(postMidnight)

        let occ = try #require(slot.occurrence(on: testDate(year: 2025, month: 12, day: 31)))
        #expect(occ.isSaturated(checkIns: [postMidnight]) == true)
    }
}
}
