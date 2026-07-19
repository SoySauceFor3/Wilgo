import Foundation
import SwiftData
import Testing
@testable import Wilgo

@MainActor
struct LegacyCycleRecordWipeTests {
    // MARK: - Helpers

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "LegacyCycleRecordWipeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, suite)
    }

    private func makeCommitment(in ctx: ModelContext) -> Commitment {
        let commitment = Commitment(
            title: "Leetcode",
            cycle: Cycle.makeDefault(.weekly),
            slots: [],
            target: Target(count: 3)
        )
        ctx.insert(commitment)
        return commitment
    }

    private func makeRecord(
        commitment: Commitment,
        outcome: CycleOutcome? = .punished,
        consumedPT: PositivityToken? = nil
    ) -> CycleRecord {
        CycleRecord(
            commitment: commitment,
            snapshotTitle: "Leetcode",
            cycleStart: Date(timeIntervalSince1970: 1_700_000_000),
            cycleEnd: Date(timeIntervalSince1970: 1_700_600_000),
            targetCount: 3,
            checkInCount: 1,
            outcome: outcome,
            reflectionText: nil,
            emojiReactions: [],
            consumedPT: consumedPT
        )
    }

    // MARK: - Tests

    @Test func wipesAllRecordsAndSetsFlagWhenUnset() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let commitment = makeCommitment(in: ctx)
        ctx.insert(makeRecord(commitment: commitment))
        ctx.insert(makeRecord(commitment: commitment))
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<CycleRecord>()).count == 2)

        LegacyCycleRecordWipe.runIfNeeded(context: ctx, defaults: defaults)

        #expect(try ctx.fetch(FetchDescriptor<CycleRecord>()).isEmpty)
        #expect(defaults.bool(forKey: LegacyCycleRecordWipe.defaultsKey))
    }

    @Test func preservesRecordsWhenFlagAlreadySet() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Flag already set — future records must not be nuked.
        defaults.set(true, forKey: LegacyCycleRecordWipe.defaultsKey)

        let commitment = makeCommitment(in: ctx)
        ctx.insert(makeRecord(commitment: commitment))
        try ctx.save()

        LegacyCycleRecordWipe.runIfNeeded(context: ctx, defaults: defaults)

        #expect(try ctx.fetch(FetchDescriptor<CycleRecord>()).count == 1)
    }

    @Test func freesConsumedPositivityTokenOnWipe() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let commitment = makeCommitment(in: ctx)
        let pt = PositivityToken(reason: "Shipped a PR")
        ctx.insert(pt)
        ctx.insert(makeRecord(commitment: commitment, outcome: .moveOn, consumedPT: pt))
        try ctx.save()
        #expect(pt.consumedByCycleRecord != nil)

        LegacyCycleRecordWipe.runIfNeeded(context: ctx, defaults: defaults)

        let remainingPTs = try ctx.fetch(FetchDescriptor<PositivityToken>())
        #expect(remainingPTs.count == 1)
        #expect(remainingPTs.first?.consumedByCycleRecord == nil)
    }

    @Test func leavesCommitmentsUntouchedOnWipe() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let commitment = makeCommitment(in: ctx)
        ctx.insert(makeRecord(commitment: commitment))
        try ctx.save()

        LegacyCycleRecordWipe.runIfNeeded(context: ctx, defaults: defaults)

        let remainingCommitments = try ctx.fetch(FetchDescriptor<Commitment>())
        #expect(remainingCommitments.count == 1)
        #expect(try ctx.fetch(FetchDescriptor<CycleRecord>()).isEmpty)
    }
}
