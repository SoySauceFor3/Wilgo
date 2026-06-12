import Foundation
import Testing
@testable import Wilgo

@MainActor
struct FCRCycleCardStateTests {
    // MARK: - Passed vs failed (derived from counts)

    @Test func isPassedWhenCheckInsMeetTarget() {
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 3)
        #expect(state.isPassed == true)
        state.checkInCount = 4
        #expect(state.isPassed == true)
    }

    @Test func isFailedWhenCheckInsBelowTarget() {
        let state = FCRCycleCardState(targetCount: 3, checkInCount: 2)
        #expect(state.isPassed == false)
    }

    // MARK: - Completion gating (failed cycles need label + reflection + PT)

    @Test func passedCycleIsAlwaysComplete() {
        // Passed cycles need no action — complete immediately
        let state = FCRCycleCardState(targetCount: 3, checkInCount: 3)
        #expect(state.isComplete == true)
    }

    @Test func failedCycleIncompleteWithoutLabel() {
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 0)
        state.reflectionText = "I was sick"
        state.hasAssignedPT = true
        state.outcome = nil
        #expect(state.isComplete == false)
    }

    @Test func failedCycleIncompleteWithoutReflection() {
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 0)
        state.outcome = .excused
        state.hasAssignedPT = true
        state.reflectionText = ""
        #expect(state.isComplete == false)
    }

    @Test func failedCycleIncompleteWithWhitespaceOnlyReflection() {
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 0)
        state.outcome = .excused
        state.hasAssignedPT = true
        state.reflectionText = "   \n  "
        #expect(state.isComplete == false)
    }

    @Test func failedCycleIncompleteWithoutPT() {
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 0)
        state.outcome = .excused
        state.reflectionText = "I was sick"
        state.hasAssignedPT = false
        #expect(state.isComplete == false)
    }

    @Test func failedCycleCompleteWithLabelReflectionAndPT() {
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 0)
        state.outcome = .punished
        state.reflectionText = "No excuse, just didn't do it"
        state.hasAssignedPT = true
        #expect(state.isComplete == true)
    }

    // MARK: - Auto-flip clears purposeful-stop fields

    @Test func flippingToPassedClearsFailureFields() {
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 0)
        state.outcome = .punished
        state.reflectionText = "Lazy"
        state.hasAssignedPT = true

        // Backfill pushes check-ins to target → flips to passed
        state.checkInCount = 3

        #expect(state.isPassed == true)
        #expect(state.outcome == nil)
        #expect(state.reflectionText.isEmpty)
        #expect(state.hasAssignedPT == false)
        #expect(state.isComplete == true)
    }

    @Test func flippingBackToFailedRequiresFieldsAgain() {
        // Start passed
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 3)
        #expect(state.isComplete == true)

        // Undo a check-in drops below target
        state.checkInCount = 2
        #expect(state.isPassed == false)
        #expect(state.isComplete == false)
    }

    // MARK: - Emoji reactions only meaningful when passed

    @Test func emojiReactionsStartEmpty() {
        let state = FCRCycleCardState(targetCount: 3, checkInCount: 3)
        #expect(state.emojiReactions.isEmpty)
    }
}
