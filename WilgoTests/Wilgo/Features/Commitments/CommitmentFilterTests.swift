import Foundation
import SwiftData
import Testing
@testable import Wilgo

// MARK: - Filter predicate (mirrors ListCommitmentView.filteredCommitments logic)

private func applyFilter(
    commitments: [Commitment],
    selectedTagIDs: Set<UUID>
) -> [Commitment] {
    if selectedTagIDs.isEmpty {
        return commitments
    }
    return commitments.filter { c in
        c.tags.contains { selectedTagIDs.contains($0.id) }
    }
}

// MARK: - Tests

@Suite
@MainActor
struct CommitmentFilterTests {
    // MARK: OR logic — single tag filter

    @Test(
        "OR logic: commitment with tag A shown when filter = {A}; commitment with tag B not shown")
    func orLogicSingleTag() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let cA = makeCommitment(in: ctx, title: "Has A", cycleKind: .weekly)
        let cB = makeCommitment(in: ctx, title: "Has B", cycleKind: .weekly)
        let tagA = Wilgo.Tag(name: "TagA", displayOrder: 0)
        let tagB = Wilgo.Tag(name: "TagB", displayOrder: 1)

        ctx.insert(tagA)
        ctx.insert(tagB)
        cA.tags.append(tagA)
        cB.tags.append(tagB)
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<Commitment>())
        let result = applyFilter(commitments: all, selectedTagIDs: [tagA.id])

        #expect(result.count == 1)
        #expect(result.first?.title == "Has A")
    }

    // MARK: OR logic — two-tag filter

    @Test("OR logic: both commitments shown when filter = {A, B}")
    func orLogicBothTags() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let cA = makeCommitment(in: ctx, title: "Has A", cycleKind: .weekly)
        let cB = makeCommitment(in: ctx, title: "Has B", cycleKind: .weekly)
        let tagA = Wilgo.Tag(name: "TagA", displayOrder: 0)
        let tagB = Wilgo.Tag(name: "TagB", displayOrder: 1)

        ctx.insert(tagA)
        ctx.insert(tagB)
        cA.tags.append(tagA)
        cB.tags.append(tagB)
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<Commitment>())
        let result = applyFilter(commitments: all, selectedTagIDs: [tagA.id, tagB.id])

        #expect(result.count == 2)
    }

    // MARK: Empty filter — all shown including untagged

    @Test("Empty filter: all commitments shown including untagged")
    func emptyFilterShowsAll() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let cTagged = makeCommitment(in: ctx, title: "Tagged", cycleKind: .weekly)
        _ = makeCommitment(in: ctx, title: "Untagged", cycleKind: .weekly)
        let tagA = Wilgo.Tag(name: "TagA", displayOrder: 0)

        ctx.insert(tagA)
        cTagged.tags.append(tagA)
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<Commitment>())
        let result = applyFilter(commitments: all, selectedTagIDs: [])

        #expect(result.count == 2)
    }

    // MARK: Untagged commitment excluded when filter active

    @Test("Untagged commitment not shown when any filter is active")
    func untaggedExcludedWhenFilterActive() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let cTagged = makeCommitment(in: ctx, title: "Tagged", cycleKind: .weekly)
        _ = makeCommitment(in: ctx, title: "Untagged", cycleKind: .weekly)
        let tagA = Wilgo.Tag(name: "TagA", displayOrder: 0)

        ctx.insert(tagA)
        cTagged.tags.append(tagA)
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<Commitment>())
        let result = applyFilter(commitments: all, selectedTagIDs: [tagA.id])

        #expect(result.count == 1)
        #expect(result.first?.title == "Tagged")
    }

    // MARK: Pure in-memory filter logic (no SwiftData, direct struct-level test)

    @Test("Filter predicate works correctly as pure in-memory logic")
    func filterPredicatePureLogic() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let c1 = makeCommitment(in: ctx, title: "Alpha", cycleKind: .weekly)
        let c2 = makeCommitment(in: ctx, title: "Beta", cycleKind: .weekly)
        let c3 = makeCommitment(in: ctx, title: "Gamma", cycleKind: .weekly)
        let tagX = Wilgo.Tag(name: "X", displayOrder: 0)
        let tagY = Wilgo.Tag(name: "Y", displayOrder: 1)

        ctx.insert(tagX)
        ctx.insert(tagY)
        c1.tags.append(tagX)
        c2.tags.append(tagY)
        // c3 has no tags
        try ctx.save()

        let all = [c1, c2, c3]

        // Filter by X only → only Alpha
        let byX = applyFilter(commitments: all, selectedTagIDs: [tagX.id])
        #expect(byX.map(\.title) == ["Alpha"])

        // Filter by Y only → only Beta
        let byY = applyFilter(commitments: all, selectedTagIDs: [tagY.id])
        #expect(byY.map(\.title) == ["Beta"])

        // Filter by X and Y → Alpha and Beta (OR logic)
        let byXY = applyFilter(commitments: all, selectedTagIDs: [tagX.id, tagY.id])
        #expect(Set(byXY.map(\.title)) == ["Alpha", "Beta"])

        // No filter → all three
        let noFilter = applyFilter(commitments: all, selectedTagIDs: [])
        #expect(noFilter.count == 3)
    }
}
