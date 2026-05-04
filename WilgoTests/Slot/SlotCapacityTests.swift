import Foundation
import SwiftData
import Testing

@testable import Wilgo

@Suite("Slot capacity — isSaturated", .serialized)
final class SlotCapacityTests {

    // MARK: - Helpers

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Commitment.self, Slot.self, CheckIn.self,
            SlotSnooze.self, Tag.self, PositivityToken.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func tod(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 1
        c.hour = hour; c.minute = minute; c.second = 0
        return Calendar.current.date(from: c)!
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min; c.second = 0
        return Calendar.current.date(from: c)!
    }

    @MainActor
    private func makeCommitmentAndSlot(
        cap: Int?,
        start: Int = 9, end: Int = 11,
        in ctx: ModelContext
    ) -> (Commitment, Slot) {
        let slot = Slot(start: tod(hour: start), end: tod(hour: end))
        slot.maxCheckIns = cap
        let commitment = Commitment(
            title: "T",
            cycle: Cycle(kind: .daily, referencePsychDay: date(2026, 1, 1)),
            slots: [slot],
            target: QuantifiedCycle(count: 5)
        )
        ctx.insert(commitment)
        ctx.insert(slot)
        return (commitment, slot)
    }

    // MARK: - nil cap → never saturated

    @Test("maxCheckIns nil → not saturated regardless of check-ins")
    @MainActor func nilCap_neverSaturated() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (commitment, slot) = makeCommitmentAndSlot(cap: nil, in: ctx)

        let now = date(2026, 3, 5, 10)
        let ci = CheckIn(commitment: commitment, createdAt: now)
        ctx.insert(ci)

        #expect(slot.isSaturated(at: now, checkIns: [ci]) == false)
    }

    // MARK: - cap reached by in-window check-ins

    @Test("cap=1, one in-window check-in → saturated")
    @MainActor func capOne_oneInWindow_saturated() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (commitment, slot) = makeCommitmentAndSlot(cap: 1, in: ctx)

        let now = date(2026, 3, 5, 10)  // inside 9-11 window
        let ci = CheckIn(commitment: commitment, createdAt: now)
        ctx.insert(ci)

        #expect(slot.isSaturated(at: now, checkIns: [ci]) == true)
    }

    @Test("cap=2, two in-window check-ins → saturated")
    @MainActor func capTwo_twoInWindow_saturated() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (commitment, slot) = makeCommitmentAndSlot(cap: 2, in: ctx)

        let t1 = date(2026, 3, 5, 9, 30)
        let t2 = date(2026, 3, 5, 10, 30)
        let ci1 = CheckIn(commitment: commitment, createdAt: t1)
        let ci2 = CheckIn(commitment: commitment, createdAt: t2)
        ctx.insert(ci1); ctx.insert(ci2)

        #expect(slot.isSaturated(at: t2, checkIns: [ci1, ci2]) == true)
    }

    // MARK: - out-of-window check-ins do NOT saturate

    @Test("cap=1, only out-of-window check-in → not saturated")
    @MainActor func capOne_outOfWindow_notSaturated() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (commitment, slot) = makeCommitmentAndSlot(cap: 1, in: ctx)

        let outside = date(2026, 3, 5, 7)  // before 9am window
        let ci = CheckIn(commitment: commitment, createdAt: outside)
        ctx.insert(ci)

        let now = date(2026, 3, 5, 10)
        #expect(slot.isSaturated(at: now, checkIns: [ci]) == false)
    }

    // MARK: - end is exclusive

    @Test("cap=1, check-in exactly at end → not saturated")
    @MainActor func capOne_atEndBoundary_notSaturated() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (commitment, slot) = makeCommitmentAndSlot(cap: 1, in: ctx)

        let atEnd = date(2026, 3, 5, 11)  // exactly window end
        let ci = CheckIn(commitment: commitment, createdAt: atEnd)
        ctx.insert(ci)

        #expect(slot.isSaturated(at: atEnd, checkIns: [ci]) == false)
    }

    @Test("cap=1, check-in exactly at start → saturated")
    @MainActor func capOne_atStartBoundary_saturated() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (commitment, slot) = makeCommitmentAndSlot(cap: 1, in: ctx)

        let atStart = date(2026, 3, 5, 9)
        let ci = CheckIn(commitment: commitment, createdAt: atStart)
        ctx.insert(ci)

        #expect(slot.isSaturated(at: atStart, checkIns: [ci]) == true)
    }

    // MARK: - capacity is per-occurrence (different days are independent)

    @Test("cap=1, yesterday saturated does NOT saturate today")
    @MainActor func capOne_yesterdayDoesNotSaturateToday() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (commitment, slot) = makeCommitmentAndSlot(cap: 1, in: ctx)

        let yesterdayCheckIn = date(2026, 3, 4, 10)
        let ci = CheckIn(commitment: commitment, createdAt: yesterdayCheckIn)
        ctx.insert(ci)

        let today = date(2026, 3, 5, 10)
        #expect(slot.isSaturated(at: today, checkIns: [ci]) == false)
    }

    // MARK: - whole-day slot

    @Test("whole-day slot, cap=1, any same-day check-in → saturated")
    @MainActor func wholeDay_capOne_anyCheckInSaturates() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Whole-day sentinel: start == end
        let slot = Slot(start: tod(hour: 0), end: tod(hour: 0))
        slot.maxCheckIns = 1
        let commitment = Commitment(
            title: "T",
            cycle: Cycle(kind: .daily, referencePsychDay: date(2026, 1, 1)),
            slots: [slot],
            target: QuantifiedCycle(count: 1)
        )
        ctx.insert(commitment); ctx.insert(slot)

        let nowMorning = date(2026, 3, 5, 7)
        let ciMorning = CheckIn(commitment: commitment, createdAt: nowMorning)
        ctx.insert(ciMorning)

        let nowEvening = date(2026, 3, 5, 22)
        #expect(slot.isSaturated(at: nowEvening, checkIns: [ciMorning]) == true)
    }
}
