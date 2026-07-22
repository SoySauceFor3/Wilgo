import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite(.serialized)
@MainActor
final class CheckInUndoManagerTests {
    // Swift Testing instantiates a fresh suite instance per test, so this container lives for the
    // whole test. It MUST be held strongly: `ModelContext` only weakly references its container, and
    // a released container invalidates every inserted model — reading `.id`/`.commitment` then trips
    // a SwiftData assertion (see repo SwiftData test rule). Do not refactor into a helper that returns
    // the container by value and let call sites drop it.
    private let container: ModelContainer
    private let context: ModelContext
    private let commitment: Commitment
    private let manager = CheckInUndoManager()

    init() throws {
        container = try makeTestContainer()
        context = container.mainContext
        commitment = makeCommitment(in: context)
        try context.save()
    }

    /// Creates, inserts, and persists a check-in on the shared commitment, mirroring the production
    /// insert path (`CheckIn.insert` also appends to the inverse relationship before enqueue).
    @discardableResult
    private func makeCheckIn() throws -> CheckIn {
        let checkIn = CheckIn(commitment: commitment)
        context.insert(checkIn)
        commitment.checkIns.append(checkIn)
        try context.save()
        return checkIn
    }

    // MARK: - enqueue

    @Test("enqueue appends a notice keyed by the check-in id")
    func enqueueAppendsNotice() throws {
        let checkIn = try makeCheckIn()

        manager.enqueue(checkIn: checkIn, title: "Saved", context: context)

        #expect(manager.notices.count == 1)
        let notice = try #require(manager.notices.first)
        #expect(notice.id == checkIn.id)
        #expect(notice.title == "Saved")
        #expect(notice.kind == .undo)
    }

    @Test("enqueuing twice for the same check-in replaces rather than duplicates")
    func enqueueSameCheckInReplaces() throws {
        let checkIn = try makeCheckIn()

        manager.enqueue(checkIn: checkIn, title: "First", context: context)
        manager.enqueue(checkIn: checkIn, title: "Second", context: context)

        #expect(manager.notices.count == 1)
        #expect(manager.notices.first?.title == "Second")
    }

    @Test("enqueuing distinct check-ins keeps both notices")
    func enqueueDistinctKeepsBoth() throws {
        let first = try makeCheckIn()
        let second = try makeCheckIn()

        manager.enqueue(checkIn: first, title: "First", context: context)
        manager.enqueue(checkIn: second, title: "Second", context: context)

        #expect(manager.notices.count == 2)
        #expect(Set(manager.notices.map(\.id)) == [first.id, second.id])
    }

    // MARK: - undo

    @Test("undo deletes the check-in from the context and removes the notice")
    func undoDeletesCheckInAndRemovesNotice() throws {
        let checkIn = try makeCheckIn()
        manager.enqueue(checkIn: checkIn, title: "Saved", context: context)
        let notice = try #require(manager.notices.first)

        manager.undo(notice)

        #expect(manager.notices.isEmpty)
        let remaining = try context.fetch(FetchDescriptor<CheckIn>())
        #expect(remaining.isEmpty)
    }

    @Test("undo is idempotent — a second undo of the same notice is a no-op")
    func undoIsIdempotent() throws {
        let checkIn = try makeCheckIn()
        manager.enqueue(checkIn: checkIn, title: "Saved", context: context)
        let notice = try #require(manager.notices.first)

        manager.undo(notice)
        manager.undo(notice)  // Must not crash or double-delete.

        #expect(manager.notices.isEmpty)
        #expect(try context.fetch(FetchDescriptor<CheckIn>()).isEmpty)
    }

    @Test("undo ignores a notice whose kind is not .undo")
    func undoIgnoresNonUndoKind() throws {
        let checkIn = try makeCheckIn()
        manager.enqueue(checkIn: checkIn, title: "Saved", context: context)
        // Fabricate an .info notice with the same id; undo should bail on kind.
        let infoNotice = CheckInUndoManager.Notice(
            id: checkIn.id, createdAt: Date(), title: "Info", kind: .info
        )

        manager.undo(infoNotice)

        #expect(manager.notices.count == 1)
        #expect(try context.fetch(FetchDescriptor<CheckIn>()).count == 1)
    }

    @Test("undo of a notice with no tracked state is a no-op")
    func undoUnknownNoticeIsNoOp() throws {
        let checkIn = try makeCheckIn()
        manager.enqueue(checkIn: checkIn, title: "Saved", context: context)
        let unknown = CheckInUndoManager.Notice(
            id: UUID(), createdAt: Date(), title: "Ghost", kind: .undo
        )

        manager.undo(unknown)

        #expect(manager.notices.count == 1)
        #expect(try context.fetch(FetchDescriptor<CheckIn>()).count == 1)
    }

    // MARK: - dismissAll

    @Test("dismissAll clears every notice without deleting any check-in")
    func dismissAllClearsNoticesButKeepsCheckIns() throws {
        let first = try makeCheckIn()
        let second = try makeCheckIn()
        manager.enqueue(checkIn: first, title: "First", context: context)
        manager.enqueue(checkIn: second, title: "Second", context: context)

        manager.dismissAll()

        #expect(manager.notices.isEmpty)
        #expect(try context.fetch(FetchDescriptor<CheckIn>()).count == 2)
    }

    // MARK: - auto-dismiss

    @Test("the notice auto-dismisses after its timeout without deleting the check-in")
    func autoDismissRemovesNoticeAfterTimeout() async throws {
        let checkIn = try makeCheckIn()
        manager.enqueue(checkIn: checkIn, title: "Saved", context: context)
        #expect(manager.notices.count == 1)

        // autoDismissDuration is 5s; poll a bit past that for the @MainActor callback to land.
        let deadline = Date().addingTimeInterval(8)
        while !manager.notices.isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)  // 0.1s
        }

        #expect(manager.notices.isEmpty)
        // Auto-dismiss must NOT delete the check-in — only user Undo does.
        #expect(try context.fetch(FetchDescriptor<CheckIn>()).count == 1)
    }
}
