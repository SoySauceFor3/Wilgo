import Foundation
import SwiftData
import Testing

@testable import Wilgo

@Suite("Commitment.stageStatus - slot capacity", .serialized)
final class CommitmentSlotCapacityStageTests {

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
            target: QuantifiedCycle(count: targetCount)
        )
        ctx.insert(commitment)
        slots.forEach { ctx.insert($0) }
        return commitment
    }

    // MARK: - Saturated current slot exits .current

    @Test("active slot with cap=1, one in-window check-in -> drops out of .current")
    @MainActor func saturatedSoleSlot_dropsToCatchUpWhenTargetUnmet() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(
            slotsWithCap: [(9, 11, 1)],
            targetCount: 2,
            in: ctx
        )

        let checkInTime = date(2026, 3, 5, 10)
        let checkIn = CheckIn(commitment: commitment, createdAt: checkInTime)
        ctx.insert(checkIn)
        commitment.checkIns = [checkIn]

        let now = date(2026, 3, 5, 10, 30)
        let status = commitment.stageStatus(now: now)
        #expect(status.category == .catchUp)
        #expect(status.nextUpSlots.isEmpty)
    }

    @Test("two slots, first cap=1 saturated -> status is .future on second")
    @MainActor func saturatedFirstSlot_secondSlotIsFuture() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(
            slotsWithCap: [(9, 11, 1), (15, 17, nil)],
            targetCount: 2,
            in: ctx
        )

        let checkInTime = date(2026, 3, 5, 10)
        let checkIn = CheckIn(commitment: commitment, createdAt: checkInTime)
        ctx.insert(checkIn)
        commitment.checkIns = [checkIn]

        let now = date(2026, 3, 5, 10, 30)
        let status = commitment.stageStatus(now: now)
        #expect(status.category == .future)
        #expect(status.nextUpSlots.allSatisfy { $0.start > now })
    }

    // MARK: - cap reached but target met -> .metGoal precedence

    @Test("cap=1 saturated AND target met -> .metGoal")
    @MainActor func saturatedAndTargetMet_isMetGoal() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(
            slotsWithCap: [(9, 11, 1)],
            targetCount: 1,
            in: ctx
        )

        let checkInTime = date(2026, 3, 5, 10)
        let checkIn = CheckIn(commitment: commitment, createdAt: checkInTime)
        ctx.insert(checkIn)
        commitment.checkIns = [checkIn]

        let now = date(2026, 3, 5, 10, 30)
        let status = commitment.stageStatus(now: now)
        #expect(status.category == .metGoal)
    }

    // MARK: - out-of-window check-in does NOT saturate

    @Test("cap=1 with only out-of-window check-in -> slot remains .current")
    @MainActor func outOfWindowCheckIn_doesNotSaturate() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(
            slotsWithCap: [(17, 20, 1)],
            targetCount: 2,
            in: ctx
        )

        let backfillTime = date(2026, 3, 5, 12)
        let checkIn = CheckIn(commitment: commitment, createdAt: backfillTime, source: .backfill)
        ctx.insert(checkIn)
        commitment.checkIns = [checkIn]

        let now = date(2026, 3, 5, 18)
        let status = commitment.stageStatus(now: now)
        #expect(status.category == .current)
    }

    // MARK: - nil cap is unchanged behavior

    @Test("cap=nil with two in-window check-ins -> still .current")
    @MainActor func nilCap_inWindowCheckIns_stillCurrent() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(
            slotsWithCap: [(9, 11, nil)],
            targetCount: 5,
            in: ctx
        )

        let checkIn1 = CheckIn(commitment: commitment, createdAt: date(2026, 3, 5, 9, 30))
        let checkIn2 = CheckIn(commitment: commitment, createdAt: date(2026, 3, 5, 9, 45))
        ctx.insert(checkIn1)
        ctx.insert(checkIn2)
        commitment.checkIns = [checkIn1, checkIn2]

        let now = date(2026, 3, 5, 10)
        let status = commitment.stageStatus(now: now)
        #expect(status.category == .current)
    }

    // MARK: - whole-day slot with cap=1

    @Test("whole-day slot cap=1, morning check-in -> not .current at evening")
    @MainActor func wholeDayCap1_morningCheckIn_notCurrentAtEvening() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 0), end: tod(hour: 0))
        slot.maxCheckIns = 1
        let commitment = Commitment(
            title: "T",
            cycle: Cycle(kind: .daily, referencePsychDay: date(2026, 1, 1)),
            slots: [slot],
            target: QuantifiedCycle(count: 1)
        )
        ctx.insert(commitment)
        ctx.insert(slot)

        let morning = date(2026, 3, 5, 7)
        let checkIn = CheckIn(commitment: commitment, createdAt: morning)
        ctx.insert(checkIn)
        commitment.checkIns = [checkIn]

        let evening = date(2026, 3, 5, 22)
        let status = commitment.stageStatus(now: evening)
        #expect(status.category == .metGoal)
    }
}
