import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite(.serialized)
final class CommitmentSlotStatusCapacityTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Commitment.self, Slot.self, CheckIn.self,
            SlotSnooze.self, Tag.self, PositivityToken.self,
        ])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

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
    private func makeCommitment(
        slotsWithCap: [(start: Int, end: Int, cap: Int?)],
        targetCount: Int,
        in ctx: ModelContext
    ) -> Commitment {
        let anchor = date(2026, 1, 1)
        let slots = slotsWithCap.map { def -> Slot in
            let slot = Slot(start: tod(hour: def.start), end: tod(hour: def.end))
            slot.maxCheckIns = def.cap
            return slot
        }
        let commitment = Commitment(
            title: "T",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: slots,
            target: Target(count: targetCount)
        )
        ctx.insert(commitment)
        slots.forEach { ctx.insert($0) }
        return commitment
    }

    // MARK: - saturated slot drops from current

    @Test("active slot cap=1 saturated → kind .noSlotToday, remainingSlots empty")
    @MainActor func saturatedSoleSlot_noSlotToday() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(slotsWithCap: [(9, 11, 1)], targetCount: 2, in: ctx)

        let checkIn = CheckIn(commitment: commitment, createdAt: date(2026, 3, 5, 10))
        ctx.insert(checkIn)
        commitment.checkIns = [checkIn]

        let slotSt = commitment.slotStatus(now: date(2026, 3, 5, 10, 30))
        #expect(slotSt.kind == .noSlotToday)
        #expect(slotSt.remainingSlots.isEmpty)
    }

    @Test("two slots, first cap=1 saturated → kind .beforeNextToday on second")
    @MainActor func saturatedFirstSlot_secondSlotIsBeforeNextToday() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(slotsWithCap: [(9, 11, 1), (15, 17, nil)], targetCount: 2, in: ctx)

        let checkIn = CheckIn(commitment: commitment, createdAt: date(2026, 3, 5, 10))
        ctx.insert(checkIn)
        commitment.checkIns = [checkIn]

        let now = date(2026, 3, 5, 10, 30)
        let slotSt = commitment.slotStatus(now: now)
        #expect(slotSt.kind == .beforeNextToday)
        #expect(slotSt.remainingSlots.allSatisfy { $0.start > now })
    }

    // MARK: - cap reached + target met

    @Test("cap=1 saturated AND target met → goalProgress.isMet")
    @MainActor func saturatedAndTargetMet_goalIsMet() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(slotsWithCap: [(9, 11, 1)], targetCount: 1, in: ctx)

        let checkIn = CheckIn(commitment: commitment, createdAt: date(2026, 3, 5, 10))
        ctx.insert(checkIn)
        commitment.checkIns = [checkIn]

        #expect(commitment.goalProgress(now: date(2026, 3, 5, 10, 30)).isMet)
    }

    // MARK: - out-of-window check-in does not saturate

    @Test("cap=1 with only out-of-window check-in → slot remains .insideSlot")
    @MainActor func outOfWindowCheckIn_doesNotSaturate() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(slotsWithCap: [(17, 20, 1)], targetCount: 2, in: ctx)

        let checkIn = CheckIn(commitment: commitment, createdAt: date(2026, 3, 5, 12), source: .backfill)
        ctx.insert(checkIn)
        commitment.checkIns = [checkIn]

        let slotSt = commitment.slotStatus(now: date(2026, 3, 5, 18))
        #expect(slotSt.kind == .insideSlot)
    }

    // MARK: - nil cap (unlimited)

    @Test("cap=nil with two in-window check-ins → slot still .insideSlot")
    @MainActor func nilCap_inWindowCheckIns_stillInsideSlot() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(slotsWithCap: [(9, 11, nil)], targetCount: 5, in: ctx)

        let checkIn1 = CheckIn(commitment: commitment, createdAt: date(2026, 3, 5, 9, 30))
        let checkIn2 = CheckIn(commitment: commitment, createdAt: date(2026, 3, 5, 9, 45))
        ctx.insert(checkIn1)
        ctx.insert(checkIn2)
        commitment.checkIns = [checkIn1, checkIn2]

        let slotSt = commitment.slotStatus(now: date(2026, 3, 5, 10))
        #expect(slotSt.kind == .insideSlot)
    }

    // MARK: - whole-day slot + cap

    @Test("whole-day slot cap=1, morning check-in → goalProgress.isMet at evening")
    @MainActor func wholeDayCap1_morningCheckIn_goalMetAtEvening() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 0), end: tod(hour: 0))
        slot.maxCheckIns = 1
        let commitment = Commitment(
            title: "T",
            cycle: Cycle(kind: .daily, referencePsychDay: date(2026, 1, 1)),
            slots: [slot],
            target: Target(count: 1)
        )
        ctx.insert(commitment)
        ctx.insert(slot)

        let checkIn = CheckIn(commitment: commitment, createdAt: date(2026, 3, 5, 7))
        ctx.insert(checkIn)
        commitment.checkIns = [checkIn]

        #expect(commitment.goalProgress(now: date(2026, 3, 5, 22)).isMet)
    }
}
