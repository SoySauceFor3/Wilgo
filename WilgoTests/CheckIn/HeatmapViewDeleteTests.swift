import Foundation
import SwiftData
import Testing

@testable import Wilgo

// MARK: - Helpers

@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema([
        Commitment.self,
        Slot.self,
        CheckIn.self,
        PositivityToken.self,
        Tag.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

@MainActor
private func makeCommitmentWithCheckIn(ctx: ModelContext) -> (Commitment, CheckIn) {
    let cycle = Cycle(kind: .daily, referencePsychDay: Date())
    let commitment = Commitment(
        title: "Run",
        cycle: cycle,
        slots: [],
        target: QuantifiedCycle(count: 1)
    )
    ctx.insert(commitment)

    let checkIn = CheckIn(commitment: commitment, createdAt: Date(), source: .app)
    ctx.insert(checkIn)
    commitment.checkIns.append(checkIn)
    return (commitment, checkIn)
}

// MARK: - Tests

@Suite("HeatmapViewDelete")
@MainActor
struct HeatmapViewDeleteTests {

    /// Deleting a CheckIn via modelContext.delete removes it from the store.
    /// This mirrors the onDelete closure wired in CommitmentHeatmapView.
    @Test func deleteCheckInFromContext() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let (_, checkIn) = makeCommitmentWithCheckIn(ctx: ctx)
        try ctx.save()

        // Verify it exists first.
        var fetched = try ctx.fetch(FetchDescriptor<CheckIn>())
        #expect(fetched.count == 1)

        // Simulate the onDelete closure from CommitmentHeatmapView.
        ctx.delete(checkIn)
        try ctx.save()

        fetched = try ctx.fetch(FetchDescriptor<CheckIn>())
        #expect(fetched.count == 0)
    }

    /// After deletion the commitment's checkIns relationship no longer contains the deleted item.
    @Test func deleteCheckInUpdatesCommitmentRelationship() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let (commitment, checkIn) = makeCommitmentWithCheckIn(ctx: ctx)
        try ctx.save()

        #expect(commitment.checkIns.count == 1)

        ctx.delete(checkIn)
        try ctx.save()

        #expect(commitment.checkIns.count == 0)
    }

    /// A second CheckIn inserted after the first is deleted confirms isolated deletion.
    @Test func onlyTargetedCheckInIsDeleted() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let (commitment, checkInA) = makeCommitmentWithCheckIn(ctx: ctx)

        let checkInB = CheckIn(commitment: commitment, createdAt: Date(), source: .backfill)
        ctx.insert(checkInB)
        commitment.checkIns.append(checkInB)
        try ctx.save()

        #expect(commitment.checkIns.count == 2)

        // Simulate onDelete for only checkInA.
        ctx.delete(checkInA)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<CheckIn>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == checkInB.id)
        #expect(commitment.checkIns.count == 1)
    }
}
