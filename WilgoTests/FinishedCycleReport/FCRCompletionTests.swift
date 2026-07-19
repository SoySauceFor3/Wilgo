import Foundation
import Testing
@testable import Wilgo

@MainActor
struct FCRCompletionTests {
    @Test func canCloseWhenNoCards() {
        #expect(FCRCompletion.canClose(states: []) == true)
    }

    @Test func canCloseWhenAllPassed() {
        let states = [
            FCRCycleCardState(targetCount: 3, checkInCount: 3),
            FCRCycleCardState(targetCount: 1, checkInCount: 5),
        ]
        #expect(FCRCompletion.canClose(states: states) == true)
    }

    @Test func cannotCloseWhenAFailedCardIsIncomplete() {
        var failed = FCRCycleCardState(targetCount: 3, checkInCount: 0)
        failed.outcome = .moveOn
        // .moveOn requires reflection + PT; both missing → incomplete
        let states = [
            FCRCycleCardState(targetCount: 3, checkInCount: 3),
            failed,
        ]
        #expect(FCRCompletion.canClose(states: states) == false)
    }

    @Test func canCloseWhenAllFailedCardsComplete() {
        var failed = FCRCycleCardState(targetCount: 3, checkInCount: 1)
        failed.outcome = .punished
        failed.reflectionText = "No excuse"
        failed.hasAssignedPT = true
        let states = [
            FCRCycleCardState(targetCount: 2, checkInCount: 2),
            failed,
        ]
        #expect(FCRCompletion.canClose(states: states) == true)
    }
}
