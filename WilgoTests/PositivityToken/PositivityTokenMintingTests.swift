import Foundation
import SwiftData
import Testing

@testable import Wilgo

@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema([
        Commitment.self,
        Slot.self,
        CheckIn.self,
        PositivityToken.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

@Suite("PositivityTokenMinting")
@MainActor
struct PositivityTokenMintingTests {

    // MARK: - mintCapacity

    @Test func mintCapacity_zeroCheckIns_returnsZero() {
        #expect(PositivityTokenMinting.mintCapacity(tokenCount: 0, checkInCount: 0) == 0)
    }

    @Test func mintCapacity_equalCounts_returnsZero() {
        #expect(PositivityTokenMinting.mintCapacity(tokenCount: 3, checkInCount: 3) == 0)
    }

    @Test func mintCapacity_moreCheckInsThanTokens_returnsPositive() {
        #expect(PositivityTokenMinting.mintCapacity(tokenCount: 2, checkInCount: 5) == 3)
    }

    @Test func mintCapacity_moreTokensThanCheckIns_returnsZero_neverNegative() {
        #expect(PositivityTokenMinting.mintCapacity(tokenCount: 10, checkInCount: 3) == 0)
    }

    // MARK: - canMint

    @Test func canMint_capacityZero_returnsFalse() {
        #expect(PositivityTokenMinting.canMint(tokenCount: 5, checkInCount: 5) == false)
    }

    @Test func canMint_capacityZero_noCheckIns_returnsFalse() {
        #expect(PositivityTokenMinting.canMint(tokenCount: 0, checkInCount: 0) == false)
    }

    @Test func canMint_capacityPositive_returnsTrue() {
        #expect(PositivityTokenMinting.canMint(tokenCount: 1, checkInCount: 4) == true)
    }

    // MARK: - fetchTotalTokenCount

    @Test func fetchTotalTokenCount_emptyStore_returnsZero() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let count = try PositivityTokenMinting.fetchTotalTokenCount(context: ctx)
        #expect(count == 0)
    }

    @Test func fetchTotalTokenCount_afterInserts_returnsCorrectCount() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        ctx.insert(PositivityToken(reason: "reason A"))
        ctx.insert(PositivityToken(reason: "reason B"))
        ctx.insert(PositivityToken(reason: "reason C"))
        try ctx.save()

        let count = try PositivityTokenMinting.fetchTotalTokenCount(context: ctx)
        #expect(count == 3)
    }

    // MARK: - fetchTotalCheckInCount

    @Test func fetchTotalCheckInCount_emptyStore_returnsZero() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let count = try PositivityTokenMinting.fetchTotalCheckInCount(context: ctx)
        #expect(count == 0)
    }

    @Test func fetchTotalCheckInCount_afterInserts_returnsCorrectCount() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let commitment = Commitment(
            title: "Test Commitment",
            slots: [],
            target: Target(cycle: Cycle.anchored(.daily, at: .now), count: 1)
        )
        ctx.insert(commitment)

        ctx.insert(CheckIn(commitment: commitment))
        ctx.insert(CheckIn(commitment: commitment))
        try ctx.save()

        let count = try PositivityTokenMinting.fetchTotalCheckInCount(context: ctx)
        #expect(count == 2)
    }

    // MARK: - Integration: capacity derived from store counts

    @Test func capacityIntegration_tokensAndCheckInsInStore() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let commitment = Commitment(
            title: "Integration Commitment",
            slots: [],
            target: Target(cycle: Cycle.anchored(.daily, at: .now), count: 1)
        )
        ctx.insert(commitment)

        // 4 check-ins, 1 token → capacity should be 3
        for _ in 0..<4 {
            ctx.insert(CheckIn(commitment: commitment))
        }
        ctx.insert(PositivityToken(reason: "already minted one"))
        try ctx.save()

        let tokenCount = try PositivityTokenMinting.fetchTotalTokenCount(context: ctx)
        let checkInCount = try PositivityTokenMinting.fetchTotalCheckInCount(context: ctx)
        let capacity = PositivityTokenMinting.mintCapacity(tokenCount: tokenCount, checkInCount: checkInCount)

        #expect(tokenCount == 1)
        #expect(checkInCount == 4)
        #expect(capacity == 3)
        #expect(PositivityTokenMinting.canMint(tokenCount: tokenCount, checkInCount: checkInCount) == true)
    }
}
