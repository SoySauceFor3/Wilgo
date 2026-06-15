import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite(.serialized)
final class CommitmentArchiveTests {
    @MainActor
    private func makeCommitment(in ctx: ModelContext) -> Commitment {
        let c = Commitment(
            title: "Test",
            cycle: Cycle(kind: .daily, referencePsychDay: Date()),
            slots: [],
            target: Target(count: 1)
        )
        ctx.insert(c)
        return c
    }

    @Test("new commitment has archivedAt == nil")
    @MainActor func defaultIsNil() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(in: container.mainContext)
        #expect(c.archivedAt == nil)
    }

    @Test("setting archivedAt persists and round-trips through save/fetch")
    @MainActor func archivedAtRoundTrips() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(in: container.mainContext)
        try container.mainContext.save()

        let archiveDate = Date(timeIntervalSince1970: 1_700_000_000)
        c.archivedAt = archiveDate
        try container.mainContext.save()

        let fetched = try container.mainContext.fetch(FetchDescriptor<Commitment>())
        let saved = try #require(fetched.first)
        #expect(saved.archivedAt == archiveDate)
    }

    @Test("two commitments can independently have archivedAt set or nil")
    @MainActor func independentArchiveState() throws {
        let container = try makeTestContainer()
        let archived = makeCommitment(in: container.mainContext)
        let active = makeCommitment(in: container.mainContext)

        archived.archivedAt = Date()
        try container.mainContext.save()

        let fetched = try container.mainContext.fetch(FetchDescriptor<Commitment>())
        let fetchedArchived = try #require(fetched.first { $0.id == archived.id })
        let fetchedActive = try #require(fetched.first { $0.id == active.id })

        #expect(fetchedArchived.archivedAt != nil)
        #expect(fetchedActive.archivedAt == nil)
    }

    @Test("activePredicate / activeOnly excludes a commitment with non-nil archivedAt")
    @MainActor func activeOnlyExcludesArchived() throws {
        let container = try makeTestContainer()
        let archived = makeCommitment(in: container.mainContext)
        let active = makeCommitment(in: container.mainContext)

        archived.archivedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try container.mainContext.save()

        let fetched = try container.mainContext.fetch(.activeOnly)
        #expect(fetched.contains { $0.id == active.id })
        #expect(!fetched.contains { $0.id == archived.id })
    }

    @Test("activePredicate / activeOnly includes a commitment with nil archivedAt")
    @MainActor func activeOnlyIncludesActive() throws {
        let container = try makeTestContainer()
        let active = makeCommitment(in: container.mainContext)
        try container.mainContext.save()

        let fetched = try container.mainContext.fetch(.activeOnly)
        #expect(fetched.contains { $0.id == active.id })
    }
}
