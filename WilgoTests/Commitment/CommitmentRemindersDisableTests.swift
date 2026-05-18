import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite(.serialized)
final class CommitmentRemindersDisableTests {
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
    private func makeCommitment(remindersEnabled: Bool, in ctx: ModelContext) -> Commitment {
        let anchor = date(year: 2026, month: 1, day: 1)
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [slot],
            target: Target(count: 1),
            isRemindersEnabled: remindersEnabled
        )
        ctx.insert(c)
        ctx.insert(slot)
        return c
    }

    @Test("reminders disabled → currentWithBehind excludes it (.disabled slotKind filtered by helper)")
    @MainActor func remindersDisabled_excludedByHelper() throws {
        let container = try makeContainer()
        let c = makeCommitment(remindersEnabled: false, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        // status(now:) returns .disabled slotKind when isRemindersEnabled==false,
        // so currentWithBehind filters it out without any call-site pre-filtering.
        #expect(CommitmentAndSlot.currentWithBehind(commitments: [c], now: now).isEmpty)
    }

    @Test("reminders enabled → currentWithBehind includes it")
    @MainActor func remindersEnabled_includedByHelper() throws {
        let container = try makeContainer()
        let c = makeCommitment(remindersEnabled: true, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        #expect(CommitmentAndSlot.currentWithBehind(commitments: [c], now: now).count == 1)
    }

    @Test("reminders disabled → status.slotKind is .disabled (reminders off encoded in model)")
    @MainActor func remindersDisabled_statusSlotKindIsDisabled() throws {
        let container = try makeContainer()
        let c = makeCommitment(remindersEnabled: false, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        #expect(c.status(now: now).slotKind == .disabled)
    }
}
