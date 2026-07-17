import Foundation

/// Fires a callback at the next meaningful time boundary, then recomputes and re-arms.
///
/// One-shot-then-recompute, not a fixed repeating interval: after each fire it reads the current
/// `nextBoundary()` and re-arms to the *next* boundary. On fire it runs `onFire` (e.g. rebuild the
/// surfaces) and only then recomputes + re-arms, so the next boundary reflects any state the fire
/// settled.
///
/// The timer machinery is injected as a single `arm` closure — "schedule this fire at this date,
/// and hand back how to cancel it." Production defaults to a real one-shot `Timer` on the main run
/// loop; tests pass a closure that captures the fire handler and triggers it synchronously (no real
/// clock, no `Timer`). A single closure is a lighter test seam than a protocol with one real
/// conformer.
@MainActor
final class BoundaryTimer {
    /// Schedules `fire` to run at `date` and returns a closure that cancels that pending fire.
    /// Arming again is the caller's job to sequence; each production arm invalidates its own timer
    /// via the returned canceller.
    typealias Arm = (_ date: Date, _ fire: @escaping () async -> Void) -> () -> Void

    private let nextBoundary: () -> Date
    private let onFire: () async -> Void
    private let arm: Arm

    /// Cancels the currently-armed fire, if any. Replaced on each `schedule()`.
    private var cancelPending: (() -> Void)?

    /// - Parameters:
    ///   - nextBoundary: computes the next boundary instant, read fresh on each (re)schedule.
    ///   - onFire: run when the timer fires, before the recompute + re-arm.
    ///   - arm: the timer seam — schedule a fire at a date, return its canceller. Defaults (resolved
    ///     in the body, not as a default-argument expression, because `Timer` scheduling is
    ///     main-actor work under `-default-isolation=MainActor`) to a real one-shot main-run-loop
    ///     `Timer` that clamps a past date to fire ASAP.
    init(
        nextBoundary: @escaping () -> Date,
        onFire: @escaping () async -> Void,
        arm: Arm? = nil
    ) {
        self.nextBoundary = nextBoundary
        self.onFire = onFire
        self.arm = arm ?? BoundaryTimer.realTimerArm
    }

    /// Recompute the next boundary from current state and (re-)arm the one-shot timer to it. The
    /// single re-arm entry point: called to start the timer and by the fire handler after `onFire`.
    func schedule() {
        cancelPending?()
        let boundary = nextBoundary()
        cancelPending = arm(boundary) { [weak self] in
            await self?.handleFired()
        }
    }

    /// Cancel any pending fire.
    func cancel() {
        cancelPending?()
        cancelPending = nil
    }

    /// The fire handler: run `onFire`, then recompute and re-arm for the next boundary.
    private func handleFired() async {
        await onFire()
        schedule()
    }

    /// Production `arm`: a one-shot `Timer` on the main run loop. Clamps a past date to the immediate
    /// future so a boundary already elapsed fires ASAP rather than as an invalid negative interval.
    private static func realTimerArm(
        at date: Date, fire: @escaping () async -> Void
    ) -> () -> Void {
        let interval = max(0, date.timeIntervalSinceNow)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Task { @MainActor in await fire() }
        }
        return { timer.invalidate() }
    }
}
