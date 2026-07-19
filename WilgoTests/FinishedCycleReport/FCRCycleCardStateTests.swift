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

    // MARK: - Completion gating (matrix-driven via CycleOutcome props)
    //
    // | Label    | Reflection | PT       |
    // |----------|------------|----------|
    // | Intended | optional   | none     |
    // | Excused  | optional   | none     |
    // | Move on  | REQUIRED   | required |
    // | Punished | optional   | required |

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

    // MARK: Intended / Excused — no PT, no reflection required

    @Test func intendedCompleteWithNoPTNoReflection() {
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 0)
        state.outcome = .intended
        state.hasAssignedPT = false
        state.reflectionText = ""
        #expect(state.isReflectionRequired == false)
        #expect(state.isComplete == true)
    }

    @Test func excusedCompleteWithNoPTNoReflection() {
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 0)
        state.outcome = .excused
        state.hasAssignedPT = false
        state.reflectionText = ""
        #expect(state.isReflectionRequired == false)
        #expect(state.isComplete == true)
    }

    // MARK: Move on — reflection REQUIRED and PT required

    @Test func moveOnIncompleteWithoutReflection() {
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 0)
        state.outcome = .moveOn
        state.hasAssignedPT = true
        state.reflectionText = ""
        #expect(state.isReflectionRequired == true)
        #expect(state.isComplete == false)
    }

    @Test func moveOnIncompleteWithoutPT() {
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 0)
        state.outcome = .moveOn
        state.reflectionText = "No reason, moving on"
        state.hasAssignedPT = false
        #expect(state.isComplete == false)
    }

    @Test func moveOnCompleteWithReflectionAndPT() {
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 0)
        state.outcome = .moveOn
        state.reflectionText = "No reason, moving on"
        state.hasAssignedPT = true
        #expect(state.isComplete == true)
    }

    @Test func moveOnIncompleteWithWhitespaceOnlyReflection() {
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 0)
        state.outcome = .moveOn
        state.hasAssignedPT = true
        state.reflectionText = "   \n  "
        #expect(state.isComplete == false)
    }

    // MARK: Punished — PT required, reflection optional

    @Test func punishedIncompleteWithoutPT() {
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 0)
        state.outcome = .punished
        state.reflectionText = "I ran an extra mile"
        state.hasAssignedPT = false
        #expect(state.isComplete == false)
    }

    @Test func punishedCompleteWithPTEvenWithoutReflection() {
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 0)
        state.outcome = .punished
        state.hasAssignedPT = true
        state.reflectionText = ""
        #expect(state.isReflectionRequired == false)
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

    @Test func addReactionAppends() {
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 3)
        state.addReaction("🔥")
        state.addReaction("🔥")
        state.addReaction("💪")
        #expect(state.reactionCount("🔥") == 2)
        #expect(state.reactionCount("💪") == 1)
    }

    @Test func removeReactionDecrementsByOne() {
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 3)
        state.addReaction("🔥")
        state.addReaction("🔥")
        state.removeReaction("🔥")
        #expect(state.reactionCount("🔥") == 1)
    }

    @Test func removeReactionWhenNonePresentIsNoOp() {
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 3)
        state.removeReaction("🔥")
        #expect(state.reactionCount("🔥") == 0)
        #expect(state.emojiReactions.isEmpty)
    }

    @Test func removeReactionRemovesOnlyOneInstance() {
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 3)
        state.addReaction("🔥")
        state.addReaction("💪")
        state.addReaction("🔥")
        state.removeReaction("🔥")
        #expect(state.reactionCount("🔥") == 1)
        #expect(state.reactionCount("💪") == 1)
    }
}
