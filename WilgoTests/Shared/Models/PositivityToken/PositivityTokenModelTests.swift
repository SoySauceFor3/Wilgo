import Foundation
import SwiftData
import Testing
@testable import Wilgo

extension PositivityTokenSuite {
@MainActor
struct PositivityTokenModelTests {
    // MARK: - Basic persistence

    @Test func tokenPersistsWithReasonAndCreatedAt() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let token = PositivityToken(reason: "I stayed consistent this week")
        ctx.insert(token)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<PositivityToken>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.reason == "I stayed consistent this week")
    }

    @Test func defaultInitHasNilConsumedByCycleRecord() {
        let token = PositivityToken(reason: "growth mindset")
        #expect(token.consumedByCycleRecord == nil)
    }

    @Test func defaultInitCreatedAtIsNow() {
        let before = Date()
        let token = PositivityToken(reason: "growth mindset")
        let after = Date()
        #expect(token.createdAt >= before)
        #expect(token.createdAt <= after)
    }

    @Test func multipleTokensInsertedSuccessfully() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let reasons = ["reason A", "reason B", "reason C"]
        for reason in reasons {
            ctx.insert(PositivityToken(reason: reason))
        }
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<PositivityToken>())
        #expect(fetched.count == 3)
        #expect(Set(fetched.map(\.reason)) == Set(reasons))
    }

    @Test func customCreatedAtRoundTrips() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        var comps = DateComponents()
        comps.year = 2026
        comps.month = 1
        comps.day = 15
        let customDate = try #require(Calendar.current.date(from: comps))

        let token = PositivityToken(reason: "retrospective token", createdAt: customDate)
        ctx.insert(token)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<PositivityToken>())
        #expect(fetched.first?.createdAt == customDate)
    }

    // MARK: - Free vs consumed via relationship

    @Test func tokenIsFreeWhenNotLinkedToCycleRecord() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let token = PositivityToken(reason: "great week")
        ctx.insert(token)
        try ctx.save()

        #expect(token.consumedByCycleRecord == nil)
    }

    @Test func tokenIsConsumedWhenLinkedToCycleRecord() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let commitment = Commitment(
            title: "Leetcode", cycle: Cycle.makeDefault(.weekly),
            slots: [], target: Target(count: 3)
        )
        ctx.insert(commitment)

        let pt = PositivityToken(reason: "I cooked every day")
        ctx.insert(pt)

        let record = CycleRecord(
            commitment: commitment,
            snapshotTitle: "Leetcode",
            cycleStart: Date(), cycleEnd: Date(),
            targetCount: 3, checkInCount: 0,
            outcome: .punished, reflectionText: "Lazy.",
            emojiReactions: [], consumedPT: pt
        )
        ctx.insert(record)
        try ctx.save()

        #expect(pt.consumedByCycleRecord != nil)
    }

    // MARK: - No status/dayOfStatus

    @Test func tokenHasNoStatusProperty() {
        let token = PositivityToken(reason: "test")
        // status and dayOfStatus no longer exist — free vs consumed is via consumedByCycleRecord
        _ = token.consumedByCycleRecord  // this compiles; status would not
    }

    // MARK: - Unrestricted minting

    @Test func canMintWithoutAnyCheckIns() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        // No check-ins exist — minting should still succeed
        let token = PositivityToken(reason: "something good happened")
        ctx.insert(token)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<PositivityToken>())
        #expect(fetched.count == 1)
    }

    @Test func canMintMoreTokensThanCheckIns() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        // 0 check-ins, mint 5 tokens — no restriction
        for i in 0..<5 {
            ctx.insert(PositivityToken(reason: "win \(i)"))
        }
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<PositivityToken>())
        #expect(fetched.count == 5)
    }
}
}
