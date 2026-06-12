import Foundation
import SwiftData
import Testing
@testable import Wilgo

@MainActor
struct CycleRecordBuilderTests {
    private func makeCommitment(_ title: String, target: Int) -> Commitment {
        Commitment(
            title: title,
            cycle: Cycle.makeDefault(.weekly),
            slots: [],
            target: Target(count: target)
        )
    }

    private func makeCycle(start: Date, end: Date, target: Int, actual: Int) -> CycleReport {
        CycleReport(
            id: "c1",
            actualCheckIns: actual,
            targetCheckIns: target,
            cycleLabel: "Week",
            cycleStartPsychDay: start,
            cycleEndPsychDay: end,
            checkIns: [],
            effectiveTargetMode: .on
        )
    }

    @Test func passedCycleRecordsPassedOutcomeAndEmoji() {
        let commitment = makeCommitment("Run", target: 3)
        let start = Date()
        let end = start.addingTimeInterval(86400 * 7)
        let cycle = makeCycle(start: start, end: end, target: 3, actual: 4)

        var state = FCRCycleCardState(targetCount: 3, checkInCount: 4)
        state.emojiReactions = ["🔥", "🔥", "💪"]

        let record = CycleRecordBuilder.makeRecord(
            commitment: commitment, cycle: cycle, state: state, consumedPT: nil
        )

        #expect(record.outcome == .passed)
        #expect(record.emojiReactions == ["🔥", "🔥", "💪"])
        #expect(record.reflectionText == nil)
        #expect(record.consumedPT == nil)
        #expect(record.snapshotTitle == "Run")
        #expect(record.targetCount == 3)
        #expect(record.checkInCount == 4)
    }

    @Test func failedCycleRecordsOutcomeReflectionAndPT() {
        let commitment = makeCommitment("Leetcode", target: 3)
        let start = Date()
        let end = start.addingTimeInterval(86400 * 7)
        let cycle = makeCycle(start: start, end: end, target: 3, actual: 1)
        let pt = PositivityToken(reason: "Cooked all week")

        var state = FCRCycleCardState(targetCount: 3, checkInCount: 1)
        state.outcome = .excused
        state.reflectionText = "Was sick"
        state.hasAssignedPT = true

        let record = CycleRecordBuilder.makeRecord(
            commitment: commitment, cycle: cycle, state: state, consumedPT: pt
        )

        #expect(record.outcome == .excused)
        #expect(record.reflectionText == "Was sick")
        #expect(record.consumedPT?.reason == "Cooked all week")
        #expect(record.emojiReactions.isEmpty)
        #expect(record.checkInCount == 1)
    }

    @Test func snapshotTitleCapturedAtBuildTime() {
        let commitment = makeCommitment("Original", target: 1)
        let start = Date()
        let end = start.addingTimeInterval(86400 * 7)
        let cycle = makeCycle(start: start, end: end, target: 1, actual: 1)
        let state = FCRCycleCardState(targetCount: 1, checkInCount: 1)

        let record = CycleRecordBuilder.makeRecord(
            commitment: commitment, cycle: cycle, state: state, consumedPT: nil
        )
        // Rename after building — snapshot must not change
        commitment.title = "Renamed"

        #expect(record.snapshotTitle == "Original")
    }

    @Test func recordPersistsAndLinksPT() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let commitment = makeCommitment("Leetcode", target: 3)
        ctx.insert(commitment)
        let pt = PositivityToken(reason: "win")
        ctx.insert(pt)

        let start = Date()
        let end = start.addingTimeInterval(86400 * 7)
        let cycle = makeCycle(start: start, end: end, target: 3, actual: 0)
        var state = FCRCycleCardState(targetCount: 3, checkInCount: 0)
        state.outcome = .punished
        state.reflectionText = "No excuse"
        state.hasAssignedPT = true

        let record = CycleRecordBuilder.makeRecord(
            commitment: commitment, cycle: cycle, state: state, consumedPT: pt
        )
        ctx.insert(record)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<CycleRecord>())
        #expect(fetched.count == 1)
        // PT now reports consumed via the inverse relationship
        #expect(pt.consumedByCycleRecord != nil)
    }
}
