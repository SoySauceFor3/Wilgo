import Foundation
import SwiftData
import Testing
@testable import Wilgo

private func makeCycleStart() -> Date {
    var comps = DateComponents()
    comps.year = 2026
    comps.month = 5
    comps.day = 26
    return Calendar.current.date(from: comps)!
}

private func makeCycleEnd() -> Date {
    var comps = DateComponents()
    comps.year = 2026
    comps.month = 6
    comps.day = 2
    return Calendar.current.date(from: comps)!
}

@MainActor
struct CycleRecordModelTests {
    // MARK: - Basic persistence

    @Test func cycleRecordPersistsWithCorrectFields() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(in: ctx, title: "Leetcode", targetCount: 3, cycleKind: .weekly)

        let record = CycleRecord(
            commitment: commitment,
            snapshotTitle: "Leetcode",
            cycleStart: makeCycleStart(),
            cycleEnd: makeCycleEnd(),
            targetCount: 3,
            checkInCount: 1,
            outcome: .punished,
            reflectionText: "Just lazy.",
            emojiReactions: [],
            consumedPT: nil
        )
        ctx.insert(record)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<CycleRecord>())
        let r = try #require(fetched.first)
        #expect(r.snapshotTitle == "Leetcode")
        #expect(r.targetCount == 3)
        #expect(r.checkInCount == 1)
        #expect(r.outcome == .punished)
        #expect(r.reflectionText == "Just lazy.")
        #expect(r.emojiReactions.isEmpty)
        #expect(r.consumedPT == nil)
    }

    @Test func passedCycleRecordPersists() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(in: ctx, title: "Leetcode", targetCount: 3, cycleKind: .weekly)

        let record = CycleRecord(
            commitment: commitment,
            snapshotTitle: "Morning Run",
            cycleStart: makeCycleStart(),
            cycleEnd: makeCycleEnd(),
            targetCount: 3,
            checkInCount: 4,
            outcome: nil,
            reflectionText: nil,
            emojiReactions: ["🔥", "🔥", "💪"],
            consumedPT: nil
        )
        ctx.insert(record)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<CycleRecord>())
        let r = try #require(fetched.first)
        #expect(r.outcome == nil)
        #expect(r.reflectionText == nil)
        #expect(r.emojiReactions == ["🔥", "🔥", "💪"])
    }

    // MARK: - Snapshot title survives commitment title change

    @Test func snapshotTitleSurvivesCommitmentTitleChange() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(in: ctx, title: "Leetcode", targetCount: 3, cycleKind: .weekly)

        let record = CycleRecord(
            commitment: commitment,
            snapshotTitle: commitment.title,
            cycleStart: makeCycleStart(),
            cycleEnd: makeCycleEnd(),
            targetCount: 3,
            checkInCount: 1,
            outcome: .excused,
            reflectionText: "Was sick.",
            emojiReactions: [],
            consumedPT: nil
        )
        ctx.insert(record)
        try ctx.save()

        commitment.title = "DSA Practice"
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<CycleRecord>())
        #expect(fetched.first?.snapshotTitle == "Leetcode")
        #expect(commitment.title == "DSA Practice")
    }

    // MARK: - Snapshot counts are fixed at creation time

    @Test func checkInCountDoesNotChangeWhenCheckInsAddedAfterFCR() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(in: ctx, title: "Leetcode", targetCount: 3, cycleKind: .weekly)

        let record = CycleRecord(
            commitment: commitment,
            snapshotTitle: "Leetcode",
            cycleStart: makeCycleStart(),
            cycleEnd: makeCycleEnd(),
            targetCount: 3,
            checkInCount: 1,
            outcome: .punished,
            reflectionText: "Lazy.",
            emojiReactions: [],
            consumedPT: nil
        )
        ctx.insert(record)
        try ctx.save()

        // Simulate a backfill after FCR — CycleRecord.checkInCount must NOT change
        let checkIn = CheckIn(
            commitment: commitment, createdAt: makeCycleStart(), source: .backfill)
        ctx.insert(checkIn)
        commitment.checkIns.append(checkIn)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<CycleRecord>())
        #expect(fetched.first?.checkInCount == 1)
    }

    // MARK: - Cascade delete from Commitment

    @Test func deletingCommitmentCascadesToCycleRecords() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(in: ctx, title: "Leetcode", targetCount: 3, cycleKind: .weekly)

        let record = CycleRecord(
            commitment: commitment,
            snapshotTitle: "Leetcode",
            cycleStart: makeCycleStart(),
            cycleEnd: makeCycleEnd(),
            targetCount: 3,
            checkInCount: 0,
            outcome: .moveOn,
            reflectionText: "Moving on.",
            emojiReactions: [],
            consumedPT: nil
        )
        ctx.insert(record)
        try ctx.save()

        ctx.delete(commitment)
        try ctx.save()

        let remainingRecords = try ctx.fetch(FetchDescriptor<CycleRecord>())
        #expect(remainingRecords.isEmpty)
    }

    // MARK: - Deleting a CycleRecord must NOT delete its Commitment (.noAction)

    @Test func deletingCycleRecordDoesNotDeleteCommitment() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(in: ctx, title: "Leetcode", targetCount: 3, cycleKind: .weekly)

        let record = CycleRecord(
            commitment: commitment,
            snapshotTitle: "Leetcode",
            cycleStart: makeCycleStart(),
            cycleEnd: makeCycleEnd(),
            targetCount: 3,
            checkInCount: 0,
            outcome: .moveOn,
            reflectionText: "Moving on.",
            emojiReactions: [],
            consumedPT: nil
        )
        ctx.insert(record)
        try ctx.save()

        ctx.delete(record)
        try ctx.save()

        let remainingRecords = try ctx.fetch(FetchDescriptor<CycleRecord>())
        let remainingCommitments = try ctx.fetch(FetchDescriptor<Commitment>())
        #expect(remainingRecords.isEmpty)
        #expect(remainingCommitments.count == 1)
    }

    // MARK: - PT relationship

    @Test func deletingCycleRecordNullifiesPTRelationship() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(in: ctx, title: "Leetcode", targetCount: 3, cycleKind: .weekly)

        let pt = PositivityToken(reason: "I shipped a PR this week")
        ctx.insert(pt)

        let record = CycleRecord(
            commitment: commitment,
            snapshotTitle: "Leetcode",
            cycleStart: makeCycleStart(),
            cycleEnd: makeCycleEnd(),
            targetCount: 3,
            checkInCount: 1,
            outcome: .excused,
            reflectionText: "Sick.",
            emojiReactions: [],
            consumedPT: pt
        )
        ctx.insert(record)
        try ctx.save()

        // PT should be linked
        #expect(pt.consumedByCycleRecord != nil)

        ctx.delete(record)
        try ctx.save()

        // PT survives, but relationship is nullified — PT is "freed"
        let remainingPTs = try ctx.fetch(FetchDescriptor<PositivityToken>())
        #expect(remainingPTs.count == 1)
        #expect(remainingPTs.first?.consumedByCycleRecord == nil)
    }

    @Test func commitmentCycleRecordsRelationshipIsWiredUp() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(in: ctx, title: "Leetcode", targetCount: 3, cycleKind: .weekly)

        let r1 = CycleRecord(
            commitment: commitment,
            snapshotTitle: "Leetcode",
            cycleStart: makeCycleStart(),
            cycleEnd: makeCycleEnd(),
            targetCount: 3,
            checkInCount: 0,
            outcome: .punished,
            reflectionText: "No excuse.",
            emojiReactions: [],
            consumedPT: nil
        )
        let r2 = try CycleRecord(
            commitment: commitment,
            snapshotTitle: "Leetcode",
            cycleStart: makeCycleEnd(),
            cycleEnd: #require(Calendar.current.date(byAdding: .weekOfYear, value: 1, to: makeCycleEnd())),
            targetCount: 3,
            checkInCount: 3,
            outcome: nil,
            reflectionText: nil,
            emojiReactions: ["🔥"],
            consumedPT: nil
        )
        ctx.insert(r1)
        ctx.insert(r2)
        try ctx.save()

        #expect(commitment.cycleRecords.count == 2)
    }

    // MARK: - CycleOutcome Codable round-trip

    @Test func cycleOutcomeRoundTrips() throws {
        let outcomes: [CycleOutcome] = [.passed, .excused, .punished, .moveOn, .intended]
        for outcome in outcomes {
            let data = try JSONEncoder().encode(outcome)
            let decoded = try JSONDecoder().decode(CycleOutcome.self, from: data)
            #expect(decoded == outcome)
        }
    }
}
