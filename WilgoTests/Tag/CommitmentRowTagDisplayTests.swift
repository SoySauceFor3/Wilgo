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

@Suite("CommitmentRowTagDisplay", .serialized)
@MainActor
struct CommitmentRowTagDisplayTests {

    @Test("Commitment with no tags has empty tags array")
    func commitmentWithNoTagsIsEmpty() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let commitment = makeCommitment()
        ctx.insert(commitment)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Commitment>())
        #expect(fetched.first?.tags.isEmpty == true)
    }

    @Test("Tag names join correctly in sorted order")
    func tagNamesJoinInSortedOrder() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let commitment = makeCommitment()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let tagA = Wilgo.Tag(name: "Alpha", displayOrder: 0, createdAt: base)
        let tagB = Wilgo.Tag(name: "Beta", displayOrder: 1, createdAt: base.addingTimeInterval(1))

        ctx.insert(commitment)
        ctx.insert(tagA)
        ctx.insert(tagB)
        commitment.tags.append(tagA)
        commitment.tags.append(tagB)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Commitment>())
        let c = try #require(fetched.first)

        let sorted = c.tags.sorted {
            $0.displayOrder < $1.displayOrder ||
            ($0.displayOrder == $1.displayOrder && $0.createdAt < $1.createdAt)
        }
        let joined = sorted.map(\.name).joined(separator: ", ")
        #expect(joined == "Alpha, Beta")
    }

    @Test("Tag with lower displayOrder appears first")
    func lowerDisplayOrderAppearsFirst() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let commitment = makeCommitment()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let tagHigh = Wilgo.Tag(name: "High", displayOrder: 10, createdAt: base)
        let tagLow = Wilgo.Tag(name: "Low", displayOrder: 1, createdAt: base.addingTimeInterval(1))

        ctx.insert(commitment)
        ctx.insert(tagHigh)
        ctx.insert(tagLow)
        commitment.tags.append(tagHigh)
        commitment.tags.append(tagLow)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Commitment>())
        let c = try #require(fetched.first)

        let sorted = c.tags.sorted {
            $0.displayOrder < $1.displayOrder ||
            ($0.displayOrder == $1.displayOrder && $0.createdAt < $1.createdAt)
        }
        #expect(sorted.first?.name == "Low")
        #expect(sorted.last?.name == "High")
    }

    @Test("Tags with equal displayOrder sort by createdAt — older first")
    func equalDisplayOrderSortsByCreatedAt() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let commitment = makeCommitment()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let tagOlder = Wilgo.Tag(name: "Older", displayOrder: 5, createdAt: base)
        let tagNewer = Wilgo.Tag(name: "Newer", displayOrder: 5, createdAt: base.addingTimeInterval(60))

        ctx.insert(commitment)
        ctx.insert(tagOlder)
        ctx.insert(tagNewer)
        commitment.tags.append(tagNewer)
        commitment.tags.append(tagOlder)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Commitment>())
        let c = try #require(fetched.first)

        let sorted = c.tags.sorted {
            $0.displayOrder < $1.displayOrder ||
            ($0.displayOrder == $1.displayOrder && $0.createdAt < $1.createdAt)
        }
        #expect(sorted.first?.name == "Older")
        #expect(sorted.last?.name == "Newer")
    }
}
