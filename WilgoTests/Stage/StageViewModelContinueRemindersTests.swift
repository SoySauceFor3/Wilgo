import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite(.serialized)
final class StageViewModelContinueRemindersTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, SlotSnooze.self, Tag.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        return Calendar.current.date(from: c)!
    }

    private func tod(hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2000
        c.month = 1
        c.day = 1
        c.hour = hour
        return Calendar.current.date(from: c)!
    }

    @Test("goal-met commitment with continueRemindersAfterGoalMet=true appears as current in Stage")
    @MainActor func goalMet_continueEnabled_appearsAsCurrent() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        ctx.insert(slot)
        let anchor = date(year: 2026, month: 1, day: 1)
        let c = Commitment(
            title: "Meditate",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [slot],
            target: Target(count: 1),
            isRemindersEnabled: true,
            continueRemindersAfterGoalMet: true
        )
        ctx.insert(c)

        let checkIn = CheckIn(commitment: c, createdAt: date(year: 2026, month: 3, day: 5, hour: 8))
        ctx.insert(checkIn)
        c.checkIns.append(checkIn)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let result = CommitmentAndSlot.currentWithBehind(
            commitments: [c].filter { $0.continueRemindersAfterGoalMet || !$0.goalProgress(now: now).isMet },
            now: now
        )
        #expect(result.count == 1)
        #expect(result.first?.commitment.title == "Meditate")
    }

    @Test("goal-met commitment with continueRemindersAfterGoalMet=false is excluded from Stage")
    @MainActor func goalMet_continueDisabled_excludedFromStage() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        ctx.insert(slot)
        let anchor = date(year: 2026, month: 1, day: 1)
        let c = Commitment(
            title: "Meditate",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [slot],
            target: Target(count: 1),
            isRemindersEnabled: true,
            continueRemindersAfterGoalMet: false
        )
        ctx.insert(c)

        let checkIn = CheckIn(commitment: c, createdAt: date(year: 2026, month: 3, day: 5, hour: 8))
        ctx.insert(checkIn)
        c.checkIns.append(checkIn)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let result = CommitmentAndSlot.currentWithBehind(
            commitments: [c].filter { $0.continueRemindersAfterGoalMet || !$0.goalProgress(now: now).isMet },
            now: now
        )
        #expect(result.isEmpty)
    }
}
