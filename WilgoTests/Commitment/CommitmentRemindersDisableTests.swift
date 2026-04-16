import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite("Commitment — isRemindersEnabled", .serialized)
final class CommitmentRemindersDisableTests {

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
        ctx.insert(c); ctx.insert(slot)
        return c
    }

    @Test("reminders disabled → helper still includes it (helpers are pure, no internal filter)")
    @MainActor func remindersDisabled_helperStillIncludes() throws {
        let container = try makeContainer()
        let c = makeCommitment(remindersEnabled: false, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        // The helper classifies by slot timing, not by isRemindersEnabled.
        // Filtering is the caller's responsibility.
        #expect(CommitmentAndSlot.currentWithBehind(commitments: [c], now: now).count == 1)
    }

    @Test("reminders disabled → excluded after call-site filter (StageViewModel pattern)")
    @MainActor func remindersDisabled_excludedAfterCallSiteFilter() throws {
        let container = try makeContainer()
        let c = makeCommitment(remindersEnabled: false, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let remindersOn = [c].filter { $0.isRemindersEnabled }
        #expect(CommitmentAndSlot.currentWithBehind(commitments: remindersOn, now: now).isEmpty)
    }

    @Test("reminders enabled → included after call-site filter")
    @MainActor func remindersEnabled_includedAfterCallSiteFilter() throws {
        let container = try makeContainer()
        let c = makeCommitment(remindersEnabled: true, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let remindersOn = [c].filter { $0.isRemindersEnabled }
        #expect(CommitmentAndSlot.currentWithBehind(commitments: remindersOn, now: now).count == 1)
    }

    @Test("reminders disabled → stageStatus itself is unaffected (filtering is upstream)")
    @MainActor func remindersDisabled_stageStatusUnchanged() throws {
        let container = try makeContainer()
        let c = makeCommitment(remindersEnabled: false, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        #expect(c.stageStatus(now: now).category == .current)
    }
}
