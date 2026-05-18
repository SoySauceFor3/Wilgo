import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite(.serialized)
final class StatusTests {
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
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    @MainActor
    private func makeCommitment(
        slots slotDefs: [(start: Int, end: Int)],
        targetCount: Int = 3,
        targetMode: TargetMode = .on,
        isRemindersEnabled: Bool = true,
        in ctx: ModelContext
    ) -> Commitment {
        let anchor = date(year: 2026, month: 1, day: 1)
        let slots = slotDefs.map { Slot(start: tod(hour: $0.start), end: tod(hour: $0.end)) }
        let c = Commitment(
            title: "Test",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: slots,
            target: Target(count: targetCount, mode: targetMode),
            isRemindersEnabled: isRemindersEnabled
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

    // MARK: - slotKind

    @Test("slot active → slotKind is insideSlot")
    @MainActor func slotActive_kindIsInsideSlot() throws {
        let container = try makeContainer()
        let c = makeCommitment(slots: [(9, 11)], in: container.mainContext)
        let status = c.status(now: date(year: 2026, month: 3, day: 5, hour: 10))
        #expect(status.slotKind == .insideSlot)
    }

    @Test("slot later today → slotKind is beforeNextToday")
    @MainActor func slotLaterToday_kindIsBeforeNextToday() throws {
        let container = try makeContainer()
        let c = makeCommitment(slots: [(14, 16)], in: container.mainContext)
        let status = c.status(now: date(year: 2026, month: 3, day: 5, hour: 10))
        #expect(status.slotKind == .beforeNextToday)
    }

    @Test("slot already passed → slotKind is noSlotToday")
    @MainActor func slotPassed_kindIsNoSlotToday() throws {
        let container = try makeContainer()
        let c = makeCommitment(slots: [(9, 11)], in: container.mainContext)
        let status = c.status(now: date(year: 2026, month: 3, day: 5, hour: 18))
        #expect(status.slotKind == .noSlotToday)
    }

    // MARK: - leftToDo

    @Test("target enabled, no check-ins → leftToDo equals target count")
    @MainActor func enabled_noCheckIns_leftToDoEqualsTarget() throws {
        let container = try makeContainer()
        let c = makeCommitment(slots: [(9, 11)], targetCount: 3, in: container.mainContext)
        let status = c.status(now: date(year: 2026, month: 3, day: 5, hour: 10))
        #expect(status.leftToDo == 3)
    }

    @Test("target enabled, goal met → leftToDo is 0")
    @MainActor func enabled_goalMet_leftToDoIsZero() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], targetCount: 1, in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 9), in: ctx)
        let status = c.status(now: date(year: 2026, month: 3, day: 5, hour: 10))
        #expect(status.leftToDo == 0)
    }

    @Test("target disabled → leftToDo is nil")
    @MainActor func disabled_leftToDoIsNil() throws {
        let container = try makeContainer()
        let c = makeCommitment(slots: [(9, 11)], targetMode: .disabled, in: container.mainContext)
        let status = c.status(now: date(year: 2026, month: 3, day: 5, hour: 10))
        #expect(status.leftToDo == nil)
    }

    // MARK: - behindCount

    @Test("slot active, leftToDo > 1 remaining slot → behindCount > 0")
    @MainActor func slotActive_leftToDoExceedsSlots_behindCountPositive() throws {
        let container = try makeContainer()
        // 1 slot today, target=3, no check-ins → leftToDo=3, remainingSlots=1 → behind=2
        let c = makeCommitment(slots: [(9, 11)], targetCount: 3, in: container.mainContext)
        let status = c.status(now: date(year: 2026, month: 3, day: 5, hour: 10))
        #expect(status.behindCount == 2)
    }

    @Test("goal met → behindCount is 0")
    @MainActor func goalMet_behindCountIsZero() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], targetCount: 1, in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 9), in: ctx)
        let status = c.status(now: date(year: 2026, month: 3, day: 5, hour: 10))
        #expect(status.behindCount == 0)
    }

    @Test("target disabled → behindCount is nil")
    @MainActor func disabled_behindCountIsNil() throws {
        let container = try makeContainer()
        let c = makeCommitment(slots: [(9, 11)], targetMode: .disabled, in: container.mainContext)
        let status = c.status(now: date(year: 2026, month: 3, day: 5, hour: 10))
        #expect(status.behindCount == nil)
    }

    // MARK: - remainingSlots

    @Test("slot active → remainingSlots contains the current slot")
    @MainActor func slotActive_remainingSlotsNonEmpty() throws {
        let container = try makeContainer()
        let c = makeCommitment(slots: [(9, 11)], in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let status = c.status(now: now)
        let slots = try #require(status.remainingSlots)
        #expect(!slots.isEmpty)
        #expect(try #require(slots.first?.start) <= now)
    }

    @Test("slot passed → remainingSlots is empty for daily cycle")
    @MainActor func slotPassed_remainingSlotsEmpty() throws {
        let container = try makeContainer()
        let c = makeCommitment(slots: [(9, 11)], in: container.mainContext)
        let status = c.status(now: date(year: 2026, month: 3, day: 5, hour: 18))
        #expect(status.remainingSlots?.isEmpty == true)
    }

    // MARK: - Parity with slotStatus + goalProgress

    @Test("status is consistent with slotStatus + goalProgress called separately")
    @MainActor func parity_consistentWithSeparateCalls() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], targetCount: 3, in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)

        let combined = c.status(now: now)
        let slot = c.slotStatus(now: now)
        let progress = c.goalProgress(now: now)

        #expect(combined.slotKind == slot.kind)
        #expect((combined.remainingSlots ?? []).count == slot.remainingSlots.count)
        #expect(combined.leftToDo == progress.leftToDo)
        let expectedBehind = progress.leftToDo.map { max(0, $0 - slot.remainingSlots.count) }
        #expect(combined.behindCount == expectedBehind)
    }

    // MARK: - isRemindersEnabled == false

    @Test("reminders disabled → slotKind is .disabled, all other fields nil")
    @MainActor func remindersDisabled_slotKindIsNoSlotToday() throws {
        let container = try makeContainer()
        // Slot is active at this time, but reminders are off
        let c = makeCommitment(
            slots: [(9, 11)], isRemindersEnabled: false, in: container.mainContext)
        let status = c.status(now: date(year: 2026, month: 3, day: 5, hour: 10))
        #expect(status.slotKind == .disabled)
        #expect(status.remainingSlots == nil)
        #expect(status.leftToDo == nil)
        #expect(status.behindCount == nil)
    }
}
