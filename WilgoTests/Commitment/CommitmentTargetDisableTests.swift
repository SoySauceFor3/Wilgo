import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite("Commitment — Target.isEnabled", .serialized)
final class CommitmentTargetDisableTests {

    private func tod(hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 1; c.hour = hour; c.minute = 0; c.second = 0
        return Calendar.current.date(from: c)!
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = 0; c.second = 0
        return Calendar.current.date(from: c)!
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, SlotSnooze.self, Tag.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    @MainActor
    private func makeCommitment(targetEnabled: Bool, slotHour: Int = 9, in ctx: ModelContext) -> Commitment {
        let anchor = date(year: 2026, month: 1, day: 1)
        let slot = Slot(start: tod(hour: slotHour), end: tod(hour: slotHour + 2))
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [slot],
            target: Target(count: 3, isEnabled: targetEnabled)
        )
        ctx.insert(c); ctx.insert(slot)
        return c
    }

    @Test("target disabled + slot active now → .current (no goal math)")
    @MainActor func targetDisabled_slotActive_isCurrent() throws {
        let container = try makeContainer()
        let c = makeCommitment(targetEnabled: false, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let status = c.stageStatus(now: now)
        #expect(status.category == .current)
        #expect(status.behindCount == 0)
    }

    @Test("target disabled + slot in future today → .future with nextUpSlots")
    @MainActor func targetDisabled_slotFuture_isFuture() throws {
        let container = try makeContainer()
        let c = makeCommitment(targetEnabled: false, slotHour: 15, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let status = c.stageStatus(now: now)
        #expect(status.category == .future)
        #expect(!status.nextUpSlots.isEmpty)
        #expect(status.behindCount == 0)
    }

    @Test("target disabled + no slots today → .others")
    @MainActor func targetDisabled_noSlots_isOthers() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let anchor = date(year: 2026, month: 1, day: 1)
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [],
            target: Target(count: 3, isEnabled: false)
        )
        ctx.insert(c)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        #expect(c.stageStatus(now: now).category == .others)
    }

    @Test("target disabled → never .metGoal even with sufficient check-ins")
    @MainActor func targetDisabled_manyCheckIns_notMetGoal() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(targetEnabled: false, in: ctx)
        let checkIn = CheckIn(commitment: c, createdAt: date(year: 2026, month: 3, day: 5, hour: 8))
        ctx.insert(checkIn)
        c.checkIns.append(checkIn)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        #expect(c.stageStatus(now: now).category != .metGoal)
    }
}
