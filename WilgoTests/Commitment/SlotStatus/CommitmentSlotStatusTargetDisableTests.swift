import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite(.serialized)
final class CommitmentSlotStatusTargetDisableTests {
    private func tod(hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2000
        c.month = 1
        c.day = 1
        c.hour = hour
        c.minute = 0
        c.second = 0
        return Calendar.current.date(from: c)!
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        c.minute = 0
        c.second = 0
        return Calendar.current.date(from: c)!
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, SlotSnooze.self, Tag.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    @MainActor
    private func makeCommitment(targetMode: TargetMode, slotHour: Int = 9, in ctx: ModelContext) -> Commitment {
        let anchor = date(year: 2026, month: 1, day: 1)
        let slot = Slot(start: tod(hour: slotHour), end: tod(hour: slotHour + 2))
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [slot],
            target: Target(count: 3, mode: targetMode)
        )
        ctx.insert(c)
        ctx.insert(slot)
        return c
    }

    // MARK: - kind classification (mirrors target-enabled, mode-agnostic)

    @Test("target disabled + slot active now → kind .insideSlot, leftToDo nil")
    @MainActor func slotActive_insideSlot_leftToDoNil() throws {
        let container = try makeContainer()
        let c = makeCommitment(targetMode: .disabled, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        #expect(c.slotStatus(now: now).kind == .insideSlot)
        #expect(c.goalProgress(now: now).leftToDo == nil)
    }

    @Test("target disabled + slot in future today → kind .beforeNextToday, remainingSlots non-empty")
    @MainActor func slotFuture_beforeNextToday() throws {
        let container = try makeContainer()
        let c = makeCommitment(targetMode: .disabled, slotHour: 15, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let slotSt = c.slotStatus(now: now)
        #expect(slotSt.kind == .beforeNextToday)
        #expect(!slotSt.remainingSlots.isEmpty)
    }

    @Test("target disabled + no slots → kind .noSlotToday")
    @MainActor func noSlots_noSlotToday() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 1, day: 1)),
            slots: [],
            target: Target(count: 3, mode: .disabled)
        )
        ctx.insert(c)
        #expect(c.slotStatus(now: date(year: 2026, month: 3, day: 5, hour: 10)).kind == .noSlotToday)
    }

    @Test("target disabled → goalProgress.isMet always false even with sufficient check-ins")
    @MainActor func manyCheckIns_notMet() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(targetMode: .disabled, in: ctx)
        let checkIn = CheckIn(commitment: c, createdAt: date(year: 2026, month: 3, day: 5, hour: 8))
        ctx.insert(checkIn)
        c.checkIns.append(checkIn)
        #expect(!c.goalProgress(now: date(year: 2026, month: 3, day: 5, hour: 10)).isMet)
    }

    // MARK: - saturation with target disabled

    @Test("target disabled + saturated active slot → kind .noSlotToday, remainingSlots empty")
    @MainActor func saturatedActiveSlot_noSlotToday() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11), maxCheckIns: 1)
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 1, day: 1)),
            slots: [slot],
            target: Target(count: 3, mode: .disabled)
        )
        ctx.insert(c)
        ctx.insert(slot)
        let checkIn = CheckIn(commitment: c, createdAt: date(year: 2026, month: 3, day: 5, hour: 10))
        ctx.insert(checkIn)
        c.checkIns = [checkIn]

        let slotSt = c.slotStatus(now: date(year: 2026, month: 3, day: 5, hour: 10))
        #expect(slotSt.kind == .noSlotToday)
        #expect(slotSt.remainingSlots.isEmpty)
    }

    @Test("target disabled + saturated active slot, future slot present → kind .beforeNextToday")
    @MainActor func saturatedActiveSlot_keepsFutureSlot() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let morning = Slot(start: tod(hour: 9), end: tod(hour: 11), maxCheckIns: 1)
        let afternoon = Slot(start: tod(hour: 15), end: tod(hour: 17))
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 1, day: 1)),
            slots: [morning, afternoon],
            target: Target(count: 3, mode: .disabled)
        )
        ctx.insert(c)
        ctx.insert(morning)
        ctx.insert(afternoon)
        let checkIn = CheckIn(commitment: c, createdAt: date(year: 2026, month: 3, day: 5, hour: 10))
        ctx.insert(checkIn)
        c.checkIns = [checkIn]

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let slotSt = c.slotStatus(now: now)
        #expect(slotSt.kind == .beforeNextToday)
        #expect(slotSt.remainingSlots.allSatisfy { $0.start > now })
    }

    @Test("target disabled + out-of-window check-in does not saturate active slot")
    @MainActor func outOfWindowCheckIn_doesNotSaturateActiveSlot() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 17), end: tod(hour: 20), maxCheckIns: 1)
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 1, day: 1)),
            slots: [slot],
            target: Target(count: 3, mode: .disabled)
        )
        ctx.insert(c)
        ctx.insert(slot)
        let checkIn = CheckIn(commitment: c, createdAt: date(year: 2026, month: 3, day: 5, hour: 12))
        ctx.insert(checkIn)
        c.checkIns = [checkIn]

        let slotSt = c.slotStatus(now: date(year: 2026, month: 3, day: 5, hour: 18))
        #expect(slotSt.kind == .insideSlot)
        #expect(!slotSt.remainingSlots.isEmpty)
    }
}
