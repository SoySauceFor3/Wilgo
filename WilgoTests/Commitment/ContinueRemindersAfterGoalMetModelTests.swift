import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite(.serialized)
final class ContinueRemindersAfterGoalMetModelTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, SlotSnooze.self, Tag.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    @MainActor
    private func makeCommitment(continueReminders: Bool = false, in ctx: ModelContext) -> Commitment {
        let c = Commitment(
            title: "Test",
            cycle: Cycle(kind: .daily, referencePsychDay: Date()),
            slots: [],
            target: Target(count: 1),
            continueRemindersAfterGoalMet: continueReminders
        )
        ctx.insert(c)
        return c
    }

    @Test("continueRemindersAfterGoalMet defaults to false")
    @MainActor func defaultIsFalse() throws {
        let container = try makeContainer()
        let c = makeCommitment(in: container.mainContext)
        #expect(c.continueRemindersAfterGoalMet == false)
    }

    @Test("continueRemindersAfterGoalMet persists true")
    @MainActor func persistsTrue() throws {
        let container = try makeContainer()
        let c = makeCommitment(continueReminders: true, in: container.mainContext)
        try container.mainContext.save()
        let fetched = try container.mainContext.fetch(FetchDescriptor<Commitment>())
        let saved = try #require(fetched.first)
        #expect(saved.continueRemindersAfterGoalMet == true)
    }
}
