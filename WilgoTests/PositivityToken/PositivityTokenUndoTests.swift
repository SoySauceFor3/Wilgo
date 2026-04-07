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

@Suite("PositivityTokenUndo")
@MainActor
struct PositivityTokenUndoTests {

    // Verifies the NEW behavior: production undo closures only delete the check-in.
    // PTs are freestanding (no FK back to CheckIn since Commit 1), so SwiftData
    // will not cascade-delete them. Explicit context.delete(token) was removed in Commit 3.
    /// Deleting a check-in (simulating undo) does NOT delete an associated PositivityToken.
    /// The PT must still exist in the store with `.active` status after the check-in is removed.
    @Test func deletingCheckInLeavesPositivityTokenIntact() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // Set up a minimal Commitment
        let anchor = Date()
        let cycle = Cycle(kind: .daily, referencePsychDay: anchor)
        let commitment = Commitment(
            title: "Test",
            slots: [],
            target: QuantifiedCycle(cycle: cycle, count: 1),
        )
        ctx.insert(commitment)

        // Create a check-in
        let checkIn = CheckIn(commitment: commitment)
        ctx.insert(checkIn)
        commitment.checkIns.append(checkIn)

        // Create a PT (standalone — no link to checkIn since Commit 1 removed that relationship)
        let token = PositivityToken(reason: "Great job staying consistent!")
        ctx.insert(token)
        try ctx.save()

        // Simulate undo: delete only the check-in, NOT the token
        ctx.delete(checkIn)
        try ctx.save()

        // Check-in should be gone
        let checkIns = try ctx.fetch(FetchDescriptor<CheckIn>())
        #expect(checkIns.isEmpty)

        // PT must still exist and remain active
        let tokens = try ctx.fetch(FetchDescriptor<PositivityToken>())
        #expect(tokens.count == 1)
        #expect(tokens.first?.status == .active)
        #expect(tokens.first?.reason == "Great job staying consistent!")
    }

    /// Deleting a check-in when no PositivityToken exists must not crash.
    @Test func deletingCheckInWithNoPositivityTokenDoesNotCrash() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // Set up a minimal Commitment
        let anchor = Date()
        let cycle = Cycle(kind: .daily, referencePsychDay: anchor)
        let commitment = Commitment(
            title: "Test",
            slots: [],
            target: QuantifiedCycle(cycle: cycle, count: 1),
        )
        ctx.insert(commitment)

        // Create a check-in with no associated PT
        let checkIn = CheckIn(commitment: commitment)
        ctx.insert(checkIn)
        commitment.checkIns.append(checkIn)
        try ctx.save()

        // Simulate undo: delete the check-in — no PT to worry about, must not crash
        ctx.delete(checkIn)
        try ctx.save()

        // Check-in should be gone, and no tokens in the store
        let checkIns = try ctx.fetch(FetchDescriptor<CheckIn>())
        #expect(checkIns.isEmpty)

        let tokens = try ctx.fetch(FetchDescriptor<PositivityToken>())
        #expect(tokens.isEmpty)
    }

    @Test("deleting check-in with explicit PT delete (old behavior) removes PT — documents what NOT to do")
    func explicitPTDeletionRemovesToken() throws {
        // This test documents the OLD broken undo behavior.
        // Production undo closures must NOT do this — they should only delete the check-in.
        let container = try makeContainer()
        let ctx = container.mainContext

        let anchor = Date()
        let cycle = Cycle(kind: .daily, referencePsychDay: anchor)
        let commitment = Commitment(
            title: "Test",
            slots: [],
            target: QuantifiedCycle(cycle: cycle, count: 1),
        )
        ctx.insert(commitment)
        let checkIn = CheckIn(commitment: commitment)
        ctx.insert(checkIn)
        commitment.checkIns.append(checkIn)
        let token = PositivityToken(reason: "fragile", createdAt: .now)
        ctx.insert(token)
        try ctx.save()

        // Simulate OLD (broken) undo behavior: delete both
        ctx.delete(checkIn)
        ctx.delete(token)   // <-- this is what the old code did; new code must NOT do this
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<PositivityToken>())
        #expect(remaining.isEmpty, "When PT is explicitly deleted (old behavior), it's gone — this is the bug we fixed")
    }
}
