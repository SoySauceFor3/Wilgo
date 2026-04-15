import Foundation
import SwiftData
import Testing

@testable import Wilgo

// MARK: - Helpers

/// Callers must keep the returned container alive for the entire test — `ModelContext` only
/// weakly references its `ModelContainer`; releasing the container makes subsequent operations crash.
@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema([
        Commitment.self,
        Slot.self,
        CheckIn.self,
        PositivityToken.self,
        SlotSnooze.self,
        Wilgo.Tag.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

private func makeCommitment(title: String = "Test") -> Commitment {
    let anchor = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
    let cycle = Cycle(kind: .weekly, referencePsychDay: anchor)
    return Commitment(
        title: title,
        cycle: cycle,
        slots: [],
        target: QuantifiedCycle(count: 1)
    )
}

// MARK: - Tests

@Suite("TagModel", .serialized)
@MainActor
struct TagModelTests {

    // MARK: Tag persistence

    @Test("Tag persists with correct name and displayOrder")
    func tagPersistsWithCorrectAttributes() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let tag = Tag(name: "Health", displayOrder: 0)
        ctx.insert(tag)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Wilgo.Tag>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Health")
        #expect(fetched.first?.displayOrder == 0)
    }

    // MARK: Commitment.tags defaults

    @Test("Commitment.tags defaults to empty array")
    func commitmentTagsDefaultsToEmpty() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let commitment = makeCommitment()
        ctx.insert(commitment)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Commitment>())
        #expect(fetched.first?.tags.isEmpty == true)
    }

    // MARK: Adding a tag round-trips

    @Test("Adding a Tag to commitment.tags round-trips through save/fetch")
    func addingTagRoundTrips() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let commitment = makeCommitment()
        let tag = Tag(name: "Fitness", displayOrder: 0)
        ctx.insert(commitment)
        ctx.insert(tag)
        commitment.tags.append(tag)
        try ctx.save()

        let fetchedCommitments = try ctx.fetch(FetchDescriptor<Commitment>())
        #expect(fetchedCommitments.count == 1)
        #expect(fetchedCommitments.first?.tags.count == 1)
        #expect(fetchedCommitments.first?.tags.first?.name == "Fitness")

        let fetchedTags = try ctx.fetch(FetchDescriptor<Wilgo.Tag>())
        #expect(fetchedTags.count == 1)
        #expect(fetchedTags.first?.commitments.count == 1)
    }

    // MARK: Many-to-many

    @Test("Same Tag can belong to two Commitments (many-to-many)")
    func sameTagBelongsToTwoCommitments() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let c1 = makeCommitment(title: "Commitment A")
        let c2 = makeCommitment(title: "Commitment B")
        let tag = Tag(name: "Shared", displayOrder: 0)
        ctx.insert(c1)
        ctx.insert(c2)
        ctx.insert(tag)
        c1.tags.append(tag)
        c2.tags.append(tag)
        try ctx.save()

        let fetchedTags = try ctx.fetch(FetchDescriptor<Wilgo.Tag>())
        #expect(fetchedTags.count == 1)
        #expect(fetchedTags.first?.commitments.count == 2)

        let fetchedCommitments = try ctx.fetch(FetchDescriptor<Commitment>())
        for c in fetchedCommitments {
            #expect(c.tags.count == 1)
            #expect(c.tags.first?.name == "Shared")
        }
    }

    // MARK: Deleting a Commitment — Tag survives

    @Test("Deleting a Commitment: Tag survives and tag.commitments loses the entry")
    func deletingCommitmentTagSurvives() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let commitment = makeCommitment()
        let tag = Tag(name: "Resilient", displayOrder: 0)
        ctx.insert(commitment)
        ctx.insert(tag)
        commitment.tags.append(tag)
        try ctx.save()

        ctx.delete(commitment)
        try ctx.save()

        let fetchedCommitments = try ctx.fetch(FetchDescriptor<Commitment>())
        #expect(fetchedCommitments.isEmpty)

        let fetchedTags = try ctx.fetch(FetchDescriptor<Wilgo.Tag>())
        #expect(fetchedTags.count == 1)
        #expect(fetchedTags.first?.commitments.isEmpty == true)
    }

    // MARK: Deleting a Tag — Commitment survives

    @Test("Deleting a Tag: Commitment survives and commitment.tags loses the entry")
    func deletingTagCommitmentSurvives() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let commitment = makeCommitment()
        let tag = Tag(name: "Temporary", displayOrder: 0)
        ctx.insert(commitment)
        ctx.insert(tag)
        commitment.tags.append(tag)
        try ctx.save()

        ctx.delete(tag)
        try ctx.save()

        let fetchedTags = try ctx.fetch(FetchDescriptor<Wilgo.Tag>())
        #expect(fetchedTags.isEmpty)

        let fetchedCommitments = try ctx.fetch(FetchDescriptor<Commitment>())
        #expect(fetchedCommitments.count == 1)
        #expect(fetchedCommitments.first?.tags.isEmpty == true)
    }
}
