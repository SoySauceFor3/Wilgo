import Foundation
import SwiftData
import SwiftUI
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
        slots: [],
        target: QuantifiedCycle(cycle: cycle, count: 1)
    )
}

/// Applies the same reorder logic used in TagsSettingsView.onMove.
private func applyMove(tags: inout [Wilgo.Tag], fromOffsets source: IndexSet, toOffset destination: Int) {
    tags.move(fromOffsets: source, toOffset: destination)
    for (i, tag) in tags.enumerated() {
        tag.displayOrder = i
    }
}

// MARK: - Tests

@Suite("TagSettingsTests", .serialized)
@MainActor
struct TagSettingsTests {

    // MARK: Reorder: move last to first

    @Test("Reorder: moving last tag to first renumbers all displayOrders sequentially")
    func reorderLastToFirst() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let tagA = Wilgo.Tag(name: "Alpha", displayOrder: 0)
        let tagB = Wilgo.Tag(name: "Beta", displayOrder: 1)
        let tagC = Wilgo.Tag(name: "Gamma", displayOrder: 2)
        ctx.insert(tagA)
        ctx.insert(tagB)
        ctx.insert(tagC)
        try ctx.save()

        // Simulate moving last item (index 2) to first position (destination 0)
        var ordered: [Wilgo.Tag] = [tagA, tagB, tagC]
        applyMove(tags: &ordered, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        try ctx.save()

        // After move: [Gamma, Alpha, Beta]
        #expect(ordered[0].name == "Gamma")
        #expect(ordered[0].displayOrder == 0)
        #expect(ordered[1].name == "Alpha")
        #expect(ordered[1].displayOrder == 1)
        #expect(ordered[2].name == "Beta")
        #expect(ordered[2].displayOrder == 2)
    }

    // MARK: Reorder: move first to last

    @Test("Reorder: moving first tag to last renumbers all displayOrders sequentially")
    func reorderFirstToLast() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let tagA = Wilgo.Tag(name: "Alpha", displayOrder: 0)
        let tagB = Wilgo.Tag(name: "Beta", displayOrder: 1)
        let tagC = Wilgo.Tag(name: "Gamma", displayOrder: 2)
        ctx.insert(tagA)
        ctx.insert(tagB)
        ctx.insert(tagC)
        try ctx.save()

        // Simulate moving first item (index 0) to last position (destination 3)
        var ordered: [Wilgo.Tag] = [tagA, tagB, tagC]
        applyMove(tags: &ordered, fromOffsets: IndexSet(integer: 0), toOffset: 3)
        try ctx.save()

        // After move: [Beta, Gamma, Alpha]
        #expect(ordered[0].name == "Beta")
        #expect(ordered[0].displayOrder == 0)
        #expect(ordered[1].name == "Gamma")
        #expect(ordered[1].displayOrder == 1)
        #expect(ordered[2].name == "Alpha")
        #expect(ordered[2].displayOrder == 2)
    }

    // MARK: Sequential renumbering always produces 0-based consecutive integers

    @Test("onMove renumbering always produces consecutive 0-based displayOrder values")
    func renumberingIsAlwaysSequential() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // Create tags with non-sequential displayOrders to start (simulating real-world drift)
        let tagA = Wilgo.Tag(name: "A", displayOrder: 5)
        let tagB = Wilgo.Tag(name: "B", displayOrder: 10)
        let tagC = Wilgo.Tag(name: "C", displayOrder: 99)
        ctx.insert(tagA)
        ctx.insert(tagB)
        ctx.insert(tagC)
        try ctx.save()

        // Move middle to end
        var ordered: [Wilgo.Tag] = [tagA, tagB, tagC]
        applyMove(tags: &ordered, fromOffsets: IndexSet(integer: 1), toOffset: 3)
        try ctx.save()

        let displayOrders = ordered.map(\.displayOrder).sorted()
        #expect(displayOrders == [0, 1, 2])
    }

    // MARK: Delete tag: commitment survives with empty tags

    @Test("Delete tag: commitment that had the tag survives with empty tags")
    func deleteTagCommitmentSurvivesWithEmptyTags() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let commitment = makeCommitment(title: "My Commitment")
        let tag = Wilgo.Tag(name: "ToDelete", displayOrder: 0)
        ctx.insert(commitment)
        ctx.insert(tag)
        commitment.tags.append(tag)
        try ctx.save()

        // Verify setup
        #expect(commitment.tags.count == 1)

        // Delete tag (as onDelete handler would)
        ctx.delete(tag)
        try ctx.save()

        // Tag is gone
        let fetchedTags = try ctx.fetch(FetchDescriptor<Wilgo.Tag>())
        #expect(fetchedTags.isEmpty)

        // Commitment survives with empty tags
        let fetchedCommitments = try ctx.fetch(FetchDescriptor<Commitment>())
        #expect(fetchedCommitments.count == 1)
        #expect(fetchedCommitments.first?.title == "My Commitment")
        #expect(fetchedCommitments.first?.tags.isEmpty == true)
    }

    // MARK: Delete dialog title reflects commitment count

    @Test("deleteDialogTitle: no commitments produces simple message")
    func deleteDialogTitleNoCommitments() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let tag = Wilgo.Tag(name: "Lonely", displayOrder: 0)
        ctx.insert(tag)
        try ctx.save()

        // Simulate the title logic from TagsSettingsView
        let count = tag.commitments.count
        let title = count == 0
            ? "Delete '\(tag.name)'?"
            : "Delete '\(tag.name)'? Used in \(count) commitment\(count == 1 ? "" : "s")."

        #expect(title == "Delete 'Lonely'?")
    }

    @Test("deleteDialogTitle: one commitment produces singular message")
    func deleteDialogTitleOneCommitment() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let commitment = makeCommitment()
        let tag = Wilgo.Tag(name: "Used", displayOrder: 0)
        ctx.insert(commitment)
        ctx.insert(tag)
        commitment.tags.append(tag)
        try ctx.save()

        let count = tag.commitments.count
        let title = count == 0
            ? "Delete '\(tag.name)'?"
            : "Delete '\(tag.name)'? Used in \(count) commitment\(count == 1 ? "" : "s")."

        #expect(title == "Delete 'Used'? Used in 1 commitment.")
    }

    @Test("deleteDialogTitle: multiple commitments produces plural message")
    func deleteDialogTitleMultipleCommitments() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let c1 = makeCommitment(title: "C1")
        let c2 = makeCommitment(title: "C2")
        let tag = Wilgo.Tag(name: "Popular", displayOrder: 0)
        ctx.insert(c1)
        ctx.insert(c2)
        ctx.insert(tag)
        c1.tags.append(tag)
        c2.tags.append(tag)
        try ctx.save()

        let count = tag.commitments.count
        let title = count == 0
            ? "Delete '\(tag.name)'?"
            : "Delete '\(tag.name)'? Used in \(count) commitment\(count == 1 ? "" : "s")."

        #expect(title == "Delete 'Popular'? Used in 2 commitments.")
    }
}
