import Foundation
import Testing
@testable import Wilgo

extension LiveUpdatesSuite.RefreshCoordinationSuite {
@Suite(.serialized)
@MainActor
final class BoundaryTimerTests {
    // MARK: - Test seam

    /// Captures the `BoundaryTimer`'s injected `arm` closure: records every date the timer armed to,
    /// and stores the latest fire handler so a test can drive "the timer fired" synchronously
    /// (awaitably) — no real clock, no `Timer`.
    private final class FakeArm {
        private(set) var scheduledDates: [Date] = []
        private(set) var cancelCount = 0
        private var pendingFire: (() async -> Void)?

        var lastScheduledDate: Date? { scheduledDates.last }

        /// The closure to hand to `BoundaryTimer(arm:)`. Records the date, stores the fire handler,
        /// and returns a canceller that clears the pending fire and counts the cancel.
        func arm(at date: Date, fire: @escaping () async -> Void) -> () -> Void {
            scheduledDates.append(date)
            pendingFire = fire
            return { [weak self] in
                self?.pendingFire = nil
                self?.cancelCount += 1
            }
        }

        /// Simulate the armed timer reaching its fire time; awaits the whole handler (onFire +
        /// reschedule) so assertions see the settled state.
        func triggerFire() async {
            guard let fire = pendingFire else { return }
            await fire()
        }
    }

    private func makeDate(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 1_000_000 + offset)
    }

    // MARK: - Tests

    @Test("schedule() arms to the computed boundary")
    func schedule_armsToComputedBoundary() {
        let fake = FakeArm()
        let boundary = makeDate(100)
        let timer = BoundaryTimer(
            nextBoundary: { boundary },
            onFire: {},
            arm: fake.arm
        )

        timer.schedule()

        #expect(fake.lastScheduledDate == boundary)
        #expect(fake.scheduledDates.count == 1)
    }

    @Test("firing invokes onFire exactly once")
    func fire_invokesOnFireOnce() async {
        let fake = FakeArm()
        var fireCount = 0
        let timer = BoundaryTimer(
            nextBoundary: { self.makeDate(100) },
            onFire: { fireCount += 1 },
            arm: fake.arm
        )

        timer.schedule()
        #expect(fireCount == 0)

        await fake.triggerFire()

        #expect(fireCount == 1)
    }

    @Test("after a fire it recomputes to the NEXT boundary (not a fixed interval)")
    func fire_reschedulesToRecomputedBoundary() async {
        let fake = FakeArm()
        // Provider returns a different Date on each successive call, proving the timer recomputes
        // from current state each cycle rather than repeating a fixed interval.
        let boundaries = [makeDate(100), makeDate(250), makeDate(999)]
        var callIndex = 0
        let timer = BoundaryTimer(
            nextBoundary: {
                defer { callIndex += 1 }
                return boundaries[min(callIndex, boundaries.count - 1)]
            },
            onFire: {},
            arm: fake.arm
        )

        timer.schedule()
        #expect(fake.lastScheduledDate == boundaries[0])

        await fake.triggerFire()
        #expect(fake.lastScheduledDate == boundaries[1])

        await fake.triggerFire()
        #expect(fake.lastScheduledDate == boundaries[2])

        #expect(fake.scheduledDates == boundaries)
    }

    @Test("cancel() cancels the pending fire")
    func cancel_cancelsPendingFire() {
        let fake = FakeArm()
        let timer = BoundaryTimer(
            nextBoundary: { self.makeDate(100) },
            onFire: {},
            arm: fake.arm
        )

        timer.schedule()
        timer.cancel()

        #expect(fake.cancelCount == 1)
    }
}
}
