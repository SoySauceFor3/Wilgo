import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite(.serialized)
final class ContinueRemindersAfterGoalMetModelTests {
    @Test("continueRemindersAfterGoalMet defaults to false")
    @MainActor func defaultIsFalse() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(in: container.mainContext)
        #expect(c.continueRemindersAfterGoalMet == false)
    }

    @Test("continueRemindersAfterGoalMet persists true")
    @MainActor func persistsTrue() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(in: container.mainContext, continueAfterGoalMet: true)
        try container.mainContext.save()
        let fetched = try container.mainContext.fetch(FetchDescriptor<Commitment>())
        let saved = try #require(fetched.first)
        #expect(saved.continueRemindersAfterGoalMet == true)
    }
}
