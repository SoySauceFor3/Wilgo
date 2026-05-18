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

    // Whole-day slot (start == end == midnight) is always active regardless of wall-clock time.
    private func makeWholeDaySlot() -> Slot {
        var c = DateComponents()
        c.year = 2000
        c.month = 1
        c.day = 1
        c.hour = 0
        let midnight = Calendar.current.date(from: c)!
        return Slot(start: midnight, end: midnight)
    }

    @Test("goal-met commitment with continueRemindersAfterGoalMet=true appears in StageViewModel.current")
    @MainActor func goalMet_continueEnabled_appearsInStage() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let slot = makeWholeDaySlot()
        ctx.insert(slot)
        let anchor = Calendar.current.startOfDay(for: Date())
        let c = Commitment(
            title: "Meditate",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [slot],
            target: Target(count: 1),
            isRemindersEnabled: true,
            continueRemindersAfterGoalMet: true
        )
        ctx.insert(c)

        // Check-in from today satisfies the daily target of 1
        let checkIn = CheckIn(commitment: c, createdAt: Date())
        ctx.insert(checkIn)
        c.checkIns.append(checkIn)

        let svm = StageViewModel()
        svm.refresh(commitments: [c])

        #expect(svm.current.count == 1)
        #expect(svm.current.first?.commitment.title == "Meditate")
    }

    @Test("goal-met commitment with continueRemindersAfterGoalMet=false is excluded from StageViewModel")
    @MainActor func goalMet_continueDisabled_excludedFromStage() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let slot = makeWholeDaySlot()
        ctx.insert(slot)
        let anchor = Calendar.current.startOfDay(for: Date())
        let c = Commitment(
            title: "Meditate",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [slot],
            target: Target(count: 1),
            isRemindersEnabled: true,
            continueRemindersAfterGoalMet: false
        )
        ctx.insert(c)

        let checkIn = CheckIn(commitment: c, createdAt: Date())
        ctx.insert(checkIn)
        c.checkIns.append(checkIn)

        let svm = StageViewModel()
        svm.refresh(commitments: [c])

        #expect(svm.current.isEmpty)
        #expect(svm.upcoming.isEmpty)
        #expect(svm.catchUp.isEmpty)
    }
}
