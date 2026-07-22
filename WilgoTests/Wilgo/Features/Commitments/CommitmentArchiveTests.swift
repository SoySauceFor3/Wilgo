import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite(.serialized)
final class CommitmentArchiveTests {
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

    @Test("archiving a commitment sets archivedAt to a non-nil date")
    @MainActor func archivingSetsArchivedAt() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(in: container.mainContext)
        try container.mainContext.save()

        c.archivedAt = Date()
        try container.mainContext.save()

        let fetched = try container.mainContext.fetch(FetchDescriptor<Commitment>())
        let saved = try #require(fetched.first { $0.id == c.id })
        #expect(saved.archivedAt != nil)
    }

    @Test("activePredicate / activeOnly includes a commitment with nil archivedAt")
    @MainActor func activeOnlyIncludesActive() throws {
        let container = try makeTestContainer()
        let active = makeCommitment(in: container.mainContext)
        try container.mainContext.save()

        let fetched = try container.mainContext.fetch(.activeOnly)
        #expect(fetched.contains { $0.id == active.id })
    }

    @Test("Unarchiving sets archivedAt back to nil")
    @MainActor func unarchivingSetsArchivedAtToNil() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(in: container.mainContext)
        try container.mainContext.save()

        c.archivedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try container.mainContext.save()

        c.archivedAt = nil
        try container.mainContext.save()

        let fetched = try container.mainContext.fetch(FetchDescriptor<Commitment>())
        let saved = try #require(fetched.first { $0.id == c.id })
        #expect(saved.archivedAt == nil)
    }

    @Test("Batch unarchive clears archivedAt only for the commitments passed in")
    @MainActor func batchUnarchiveAppliesToSelectionOnly() throws {
        let container = try makeTestContainer()

        let a = makeCommitment(in: container.mainContext)
        let b = makeCommitment(in: container.mainContext)
        let c = makeCommitment(in: container.mainContext)
        for commitment in [a, b, c] {
            commitment.archivedAt = Date(timeIntervalSince1970: 1_700_000_000)
        }
        try container.mainContext.save()

        let actions = ArchivedCommitmentsActions(modelContext: container.mainContext)
        actions.unarchive([a, c])
        try container.mainContext.save()

        let fetched = try container.mainContext.fetch(FetchDescriptor<Commitment>())
        #expect(try #require(fetched.first { $0.id == a.id }).archivedAt == nil)
        #expect(try #require(fetched.first { $0.id == b.id }).archivedAt != nil)
        #expect(try #require(fetched.first { $0.id == c.id }).archivedAt == nil)
    }

    @Test("Batch delete removes only the commitments passed in")
    @MainActor func batchDeleteAppliesToSelectionOnly() throws {
        let container = try makeTestContainer()

        let a = makeCommitment(in: container.mainContext)
        let b = makeCommitment(in: container.mainContext)
        let c = makeCommitment(in: container.mainContext)
        for commitment in [a, b, c] {
            commitment.archivedAt = Date(timeIntervalSince1970: 1_700_000_000)
        }
        try container.mainContext.save()

        let actions = ArchivedCommitmentsActions(modelContext: container.mainContext)
        actions.delete([a, c])
        try container.mainContext.save()

        let remaining = try container.mainContext.fetch(FetchDescriptor<Commitment>())
        #expect(remaining.map(\.id) == [b.id])
    }

    @Test("Single unarchive resets the cycle to a fresh default of the same kind")
    @MainActor func unarchiveResetsCycle() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(in: container.mainContext)
        c.archivedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try container.mainContext.save()
        let originalKind = c.cycle.kind

        let actions = ArchivedCommitmentsActions(modelContext: container.mainContext)
        actions.unarchive([c])
        try container.mainContext.save()

        let fetched = try container.mainContext.fetch(FetchDescriptor<Commitment>())
        let saved = try #require(fetched.first { $0.id == c.id })
        #expect(saved.archivedAt == nil)
        #expect(saved.cycle.kind == originalKind)
    }

    @Test("Archived list query returns only commitments with non-nil archivedAt, sorted by archivedAt descending")
    @MainActor func archivedListQuerySortedDescending() throws {
        let container = try makeTestContainer()

        let oldest = makeCommitment(in: container.mainContext)
        let middle = makeCommitment(in: container.mainContext)
        let newest = makeCommitment(in: container.mainContext)
        let active = makeCommitment(in: container.mainContext)

        oldest.archivedAt = Date(timeIntervalSince1970: 1_700_000_000)
        middle.archivedAt = Date(timeIntervalSince1970: 1_710_000_000)
        newest.archivedAt = Date(timeIntervalSince1970: 1_720_000_000)
        // `active` is left with archivedAt == nil.

        try container.mainContext.save()

        let fetched = try container.mainContext.fetch(
            FetchDescriptor<Commitment>(
                predicate: #Predicate<Commitment> { $0.archivedAt != nil },
                sortBy: [SortDescriptor(\.archivedAt, order: .reverse)]
            )
        )

        #expect(!fetched.contains { $0.id == active.id })
        #expect(fetched.map(\.id) == [newest.id, middle.id, oldest.id])
    }
}
