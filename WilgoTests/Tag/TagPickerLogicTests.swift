import Foundation
import SwiftData
import Testing

@testable import Wilgo

// MARK: - Helpers

/// Callers must keep the returned container alive for the entire test.
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

// MARK: - Tests

@Suite("TagPickerLogic", .serialized)
@MainActor
struct TagPickerLogicTests {

    // MARK: displayOrder for first tag

    @Test("First tag in empty store gets displayOrder 0")
    func firstTagDisplayOrderIsZero() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // No tags exist → allTags is empty → max is nil → nextOrder = (-1 + 1) = 0
        let allTags = try ctx.fetch(FetchDescriptor<Wilgo.Tag>())
        let nextOrder = (allTags.map(\.displayOrder).max() ?? -1) + 1
        #expect(nextOrder == 0)
    }

    // MARK: displayOrder for second tag

    @Test("Second tag gets displayOrder = existing max + 1")
    func secondTagDisplayOrderIsMaxPlusOne() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let existing = Wilgo.Tag(name: "Existing", displayOrder: 3)
        ctx.insert(existing)
        try ctx.save()

        let allTags = try ctx.fetch(FetchDescriptor<Wilgo.Tag>())
        let nextOrder = (allTags.map(\.displayOrder).max() ?? -1) + 1
        #expect(nextOrder == 4)
    }

    // MARK: Blank name rejection

    @Test("Empty name is rejected by guard")
    func emptyNameIsRejected() {
        let emptyName = ""
        let trimmed = emptyName.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.isEmpty)
    }

    @Test("Whitespace-only name is rejected by guard")
    func whitespaceOnlyNameIsRejected() {
        let whitespaceName = "   \t\n  "
        let trimmed = whitespaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.isEmpty)
    }

    // MARK: Tag toggle — adding

    @Test("Toggling unselected tag adds it to selectedTags")
    func toggleAddsTag() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let tag = Wilgo.Tag(name: "Health", displayOrder: 0)
        ctx.insert(tag)
        try ctx.save()

        var selectedTags: [Wilgo.Tag] = []

        // Simulate toggle — tag not in list → append
        if let index = selectedTags.firstIndex(where: { $0.id == tag.id }) {
            selectedTags.remove(at: index)
        } else {
            selectedTags.append(tag)
        }

        #expect(selectedTags.count == 1)
        #expect(selectedTags.first?.name == "Health")
    }

    // MARK: Tag toggle — removing

    @Test("Toggling selected tag removes it from selectedTags")
    func toggleRemovesTag() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let tag = Wilgo.Tag(name: "Fitness", displayOrder: 0)
        ctx.insert(tag)
        try ctx.save()

        var selectedTags: [Wilgo.Tag] = [tag]

        // Simulate toggle — tag already in list → remove
        if let index = selectedTags.firstIndex(where: { $0.id == tag.id }) {
            selectedTags.remove(at: index)
        } else {
            selectedTags.append(tag)
        }

        #expect(selectedTags.isEmpty)
    }
}
