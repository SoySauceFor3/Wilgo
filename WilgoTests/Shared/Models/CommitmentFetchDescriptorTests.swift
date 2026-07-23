import Foundation
import SwiftData
import Testing
@testable import Wilgo

/// Exercises `Commitment.activePredicate` and `FetchDescriptor.activeOnly`: the shared
/// active-commitment filter used by every `@Query` site and imperative fetch. The contract
/// is simply "archivedAt == nil is active; anything else is excluded" — asserted here against
/// an in-memory container so a regression in the predicate can't silently surface archived
/// commitments in the active lists.
@Suite
@MainActor
struct CommitmentFetchDescriptorTests {
    @Test("activeOnly returns only commitments with archivedAt == nil")
    func activeOnlyExcludesArchived() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let active = makeCommitment(in: ctx, title: "Active")
        let archived = makeCommitment(in: ctx, title: "Archived")
        archived.archivedAt = Date()
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor.activeOnly)

        #expect(fetched.count == 1)
        #expect(fetched.first?.id == active.id)
    }

    @Test("activeOnly returns all commitments when none are archived")
    func activeOnlyReturnsAllWhenNoneArchived() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        _ = makeCommitment(in: ctx, title: "One")
        _ = makeCommitment(in: ctx, title: "Two")
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor.activeOnly)

        #expect(fetched.count == 2)
    }

    @Test("activeOnly returns empty when every commitment is archived")
    func activeOnlyReturnsEmptyWhenAllArchived() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let a = makeCommitment(in: ctx, title: "One")
        let b = makeCommitment(in: ctx, title: "Two")
        a.archivedAt = Date()
        b.archivedAt = Date()
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor.activeOnly)

        #expect(fetched.isEmpty)
    }

    @Test("activePredicate evaluates true only for non-archived commitments")
    func activePredicateEvaluation() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let active = makeCommitment(in: ctx, title: "Active")
        let archived = makeCommitment(in: ctx, title: "Archived")
        archived.archivedAt = Date()
        try ctx.save()

        let predicate = Commitment.activePredicate
        #expect(try predicate.evaluate(active) == true)
        #expect(try predicate.evaluate(archived) == false)
    }
}
