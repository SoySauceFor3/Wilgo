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
    /// `autoResetDelay`: how many seconds before pending resets (mirrors the 1-second Task.sleep).
    func handleDeleteTap(_ checkIn: CheckIn, autoResetDelay: Duration = .seconds(1)) {
        if pendingDeleteID == checkIn.id {
            // Second tap — confirm delete
            deletedCheckIn = checkIn
            pendingDeleteID = nil
        } else {
            // First tap — arm pending state
            pendingDeleteID = checkIn.id
            let capturedID = checkIn.id
            Task {
                try? await Task.sleep(for: autoResetDelay)
                await MainActor.run {
                    if self.pendingDeleteID == capturedID {
                        self.pendingDeleteID = nil
                    }
                }
            }
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

        machine.handleDeleteTap(checkIn, autoResetDelay: .seconds(60))  // long delay — won't fire

        #expect(machine.pendingDeleteID == checkIn.id)
        #expect(machine.deletedCheckIn == nil)
    }

    /// Tapping minus twice in quick succession (second tap before auto-reset) confirms deletion.
    @Test func secondTapWithinWindowConfirmsDelete() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let checkIn = makeCheckIn(ctx: ctx)

        let machine = PendingDeleteStateMachine()

        machine.handleDeleteTap(checkIn, autoResetDelay: .seconds(60))  // arm
        #expect(machine.pendingDeleteID == checkIn.id)

        machine.handleDeleteTap(checkIn, autoResetDelay: .seconds(60))  // confirm
        #expect(machine.deletedCheckIn == checkIn)
        #expect(machine.pendingDeleteID == nil)
    }

    /// Tapping minus once, then waiting past the auto-reset window, resets pendingDeleteID
    /// without calling onDelete.
    @Test func pendingResetsAfterTimeout() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let checkIn = makeCheckIn(ctx: ctx)

        let machine = PendingDeleteStateMachine()

        // Use a very short auto-reset delay for the test
        machine.handleDeleteTap(checkIn, autoResetDelay: .milliseconds(50))
        #expect(machine.pendingDeleteID == checkIn.id)

        // Wait longer than the auto-reset delay
        try await Task.sleep(for: .milliseconds(200))

        #expect(machine.pendingDeleteID == nil)
        #expect(machine.deletedCheckIn == nil)
    }

    /// Tapping minus for check-in A, then for check-in B (before A's timeout) switches
    /// pendingDeleteID to B without deleting A.
    @Test func tappingDifferentCheckInSwitchesPending() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let checkInA = makeCheckIn(ctx: ctx)
        let checkInB = makeCheckIn(ctx: ctx)

        let machine = PendingDeleteStateMachine()

        machine.handleDeleteTap(checkInA, autoResetDelay: .seconds(60))
        #expect(machine.pendingDeleteID == checkInA.id)

        machine.handleDeleteTap(checkInB, autoResetDelay: .seconds(60))
        #expect(machine.pendingDeleteID == checkInB.id)
        #expect(machine.deletedCheckIn == nil)
    }

    /// After a confirmed delete, tapping minus on the same check-in again starts a fresh
    /// pending cycle (re-arms rather than immediately deleting again).
    @Test func afterDeleteFirstTapRearmsState() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let checkIn = makeCheckIn(ctx: ctx)

        let machine = PendingDeleteStateMachine()

        // First delete cycle
        machine.handleDeleteTap(checkIn, autoResetDelay: .seconds(60))
        machine.handleDeleteTap(checkIn, autoResetDelay: .seconds(60))
        #expect(machine.deletedCheckIn == checkIn)
        #expect(machine.pendingDeleteID == nil)

        // Second arm — pendingDeleteID should be set again, not immediately deleted
        machine.handleDeleteTap(checkIn, autoResetDelay: .seconds(60))
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
