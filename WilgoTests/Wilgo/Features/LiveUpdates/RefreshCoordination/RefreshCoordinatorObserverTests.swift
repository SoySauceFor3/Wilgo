import Foundation
import SwiftData
import Testing
@testable import Wilgo

extension LiveUpdatesSuite.RefreshCoordinationSuite {
@Suite(.serialized)
@MainActor
final class RefreshCoordinatorObserverTests {
    // MARK: - Test doubles

    /// Captures the boundary timer's injected `arm` closure so tests can assert re-arm behavior:
    /// records every date the timer armed to, and stores the latest fire handler. Hand `arm` to
    /// `RefreshCoordinator(arm:)`.
    private final class FakeArm {
        private(set) var scheduledDates: [Date] = []
        private(set) var cancelCount = 0
        private var pendingFire: (() async -> Void)?

        var lastScheduledDate: Date? { scheduledDates.last }

        func arm(at date: Date, fire: @escaping () async -> Void) -> () -> Void {
            scheduledDates.append(date)
            pendingFire = fire
            return { [weak self] in
                self?.pendingFire = nil
                self?.cancelCount += 1
            }
        }
    }

    // MARK: - Helpers

    private func makeDate(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 1_000_000 + offset)
    }

    /// Yield the cooperative pool until `predicate` holds or we exhaust `maxYields`. Used to let a
    /// detached fire-and-forget `Task` run before asserting — no `Thread.sleep`.
    private func waitUntil(
        maxYields: Int = 100,
        _ predicate: () -> Bool
    ) async {
        var yields = 0
        while !predicate(), yields < maxYields {
            await Task.yield()
            yields += 1
        }
    }

    // MARK: - Tests

    @Test("a save on the observed context triggers the injected refresh action")
    func save_triggersRefreshAction() async throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        var refreshCount = 0
        let coordinator = RefreshCoordinator(
            arm: FakeArm().arm,
            nextBoundary: { self.makeDate(100) },
            refreshAction: { refreshCount += 1 },
            observedContext: ctx
        )
        coordinator.start()

        _ = makeCommitment(in: ctx)
        try ctx.save()

        await waitUntil { refreshCount == 1 }
        #expect(refreshCount == 1)
    }

    @Test("a save reschedules the boundary timer to the newly computed boundary")
    func save_reschedulesBoundaryTimer() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let fakeArm = FakeArm()
        // First boundary is used by start(); after a save the provider returns a NEW date, proving
        // the DB write re-armed the timer for the new commitment set.
        let boundaries = [makeDate(100), makeDate(500)]
        var callIndex = 0
        let coordinator = RefreshCoordinator(
            arm: fakeArm.arm,
            nextBoundary: {
                defer { callIndex += 1 }
                return boundaries[min(callIndex, boundaries.count - 1)]
            },
            refreshAction: {},
            observedContext: ctx
        )
        coordinator.start()
        #expect(fakeArm.lastScheduledDate == boundaries[0])

        _ = makeCommitment(in: ctx)
        try ctx.save()

        // boundaryTimer.schedule() runs synchronously inside the notification handler, so the
        // re-arm is observable immediately without waiting.
        #expect(fakeArm.lastScheduledDate == boundaries[1])
        #expect(fakeArm.scheduledDates == boundaries)
    }

    @Test("no debounce in v1: two saves trigger two refresh invocations")
    func multipleSaves_eachTriggerRefresh() async throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        var refreshCount = 0
        let coordinator = RefreshCoordinator(
            arm: FakeArm().arm,
            nextBoundary: { self.makeDate(100) },
            refreshAction: { refreshCount += 1 },
            observedContext: ctx
        )
        coordinator.start()

        let c1 = makeCommitment(in: ctx)
        try ctx.save()
        await waitUntil { refreshCount == 1 }
        #expect(refreshCount == 1)

        c1.title = "Changed"
        try ctx.save()
        await waitUntil { refreshCount == 2 }
        #expect(refreshCount == 2)
    }

    @Test("object-scoped: a save on a DIFFERENT context does NOT trigger the refresh")
    func save_onOtherContext_doesNotTrigger() async throws {
        let observedContainer = try makeTestContainer()
        let observedCtx = observedContainer.mainContext
        let otherContainer = try makeTestContainer()
        let otherCtx = ModelContext(otherContainer)
        var refreshCount = 0
        let coordinator = RefreshCoordinator(
            arm: FakeArm().arm,
            nextBoundary: { self.makeDate(100) },
            refreshAction: { refreshCount += 1 },
            observedContext: observedCtx
        )
        coordinator.start()

        // Save on a context the coordinator does NOT observe.
        let c = makeCommitment(in: otherCtx)
        _ = c
        try otherCtx.save()

        // Give any errant handler a chance to run; count must stay 0.
        await waitUntil(maxYields: 20) { refreshCount > 0 }
        #expect(refreshCount == 0)
    }

    @Test("stop() removes the observer: a later save does not trigger the refresh")
    func stop_removesObserver() async throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        var refreshCount = 0
        let coordinator = RefreshCoordinator(
            arm: FakeArm().arm,
            nextBoundary: { self.makeDate(100) },
            refreshAction: { refreshCount += 1 },
            observedContext: ctx
        )
        coordinator.start()
        coordinator.stop()

        _ = makeCommitment(in: ctx)
        try ctx.save()

        await waitUntil(maxYields: 20) { refreshCount > 0 }
        #expect(refreshCount == 0)
    }
}
}
