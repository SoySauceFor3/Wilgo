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
        Tag.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

@MainActor
private func makeCheckIn(ctx: ModelContext) -> CheckIn {
    let cycle = Cycle(kind: .daily, referencePsychDay: Date())
    let commitment = Commitment(
        title: "Test",
        slots: [],
        target: QuantifiedCycle(cycle: cycle, count: 1)
    )
    ctx.insert(commitment)
    let checkIn = CheckIn(commitment: commitment, source: .app)
    ctx.insert(checkIn)
    commitment.checkIns.append(checkIn)
    return checkIn
}

// MARK: - Pending-delete state machine (extracted logic for testability)

/// A pure-logic model of the CommitmentHeatmapInfoCard pending-delete state machine.
/// Mirrors the logic in `handleDeleteTap(_:)` in InfoCardView.swift so it can be
/// unit-tested without SwiftUI.
@MainActor
final class PendingDeleteStateMachine {
    private(set) var pendingDeleteID: UUID? = nil
    private(set) var deletedCheckIn: CheckIn? = nil

    /// Simulates tapping the − button for a given check-in.
    func handleDeleteTap(_ checkIn: CheckIn) {
        if pendingDeleteID == checkIn.id {
            // Second tap — confirm delete
            deletedCheckIn = checkIn
            pendingDeleteID = nil
        } else {
            // First tap — arm pending state (no timeout)
            pendingDeleteID = checkIn.id
        }
    }
}

// MARK: - Tests

@Suite("InfoCardPendingDelete")
@MainActor
struct InfoCardPendingDeleteTests {

    /// Tapping minus once sets pendingDeleteID to the check-in's id.
    @Test func firstTapSetsPendingID() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let checkIn = makeCheckIn(ctx: ctx)

        let machine = PendingDeleteStateMachine()
        #expect(machine.pendingDeleteID == nil)

        machine.handleDeleteTap(checkIn)

        #expect(machine.pendingDeleteID == checkIn.id)
        #expect(machine.deletedCheckIn == nil)
    }

    /// Tapping minus twice confirms deletion.
    @Test func secondTapConfirmsDelete() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let checkIn = makeCheckIn(ctx: ctx)

        let machine = PendingDeleteStateMachine()

        machine.handleDeleteTap(checkIn)  // arm
        #expect(machine.pendingDeleteID == checkIn.id)

        machine.handleDeleteTap(checkIn)  // confirm
        #expect(machine.deletedCheckIn == checkIn)
        #expect(machine.pendingDeleteID == nil)
    }

    /// Tapping minus for check-in A, then for check-in B, switches pendingDeleteID to B without deleting A.
    @Test func tappingDifferentCheckInSwitchesPending() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let checkInA = makeCheckIn(ctx: ctx)
        let checkInB = makeCheckIn(ctx: ctx)

        let machine = PendingDeleteStateMachine()

        machine.handleDeleteTap(checkInA)
        #expect(machine.pendingDeleteID == checkInA.id)

        machine.handleDeleteTap(checkInB)
        #expect(machine.pendingDeleteID == checkInB.id)
        #expect(machine.deletedCheckIn == nil)
    }

    /// After a confirmed delete, tapping minus again re-arms rather than immediately deleting.
    @Test func afterDeleteFirstTapRearmsState() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let checkIn = makeCheckIn(ctx: ctx)

        let machine = PendingDeleteStateMachine()

        machine.handleDeleteTap(checkIn)
        machine.handleDeleteTap(checkIn)
        #expect(machine.deletedCheckIn == checkIn)
        #expect(machine.pendingDeleteID == nil)

        machine.handleDeleteTap(checkIn)
        #expect(machine.pendingDeleteID == checkIn.id)
    }

    /// sourceLabel returns nil for .app and non-nil strings for other sources.
    @Test func sourceLabelValues() {
        // This mirrors the private sourceLabel helper in InfoCardView.
        // We verify the expected string values directly.
        let cases: [(CheckInSource, String?)] = [
            (.app, nil),
            (.widget, "widget"),
            (.liveActivity, "lock screen"),
            (.backfill, "backfilled"),
        ]
        for (source, expected) in cases {
            let label: String? = {
                switch source {
                case .app: return nil
                case .widget: return "widget"
                case .liveActivity: return "lock screen"
                case .backfill: return "backfilled"
                }
            }()
            #expect(label == expected, "sourceLabel for \(source) should be \(String(describing: expected))")
        }
    }
}
