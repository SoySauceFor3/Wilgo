import Foundation
import SwiftData

/// Decides WHEN to rebuild every user-facing surface (`CommitmentChangeRefresher.refreshAll()`),
/// wiring two standalone units:
///   - a `BoundaryTimer` that wakes at the next meaningful time boundary — the next slot edge or
///     the next cycle/midnight boundary, folded together by `StageCharacterization.nextStageRefreshTime` —
///     then recomputes and re-arms; and
///   - a `ModelContextSaveObserver` that reacts to SwiftData `didSave` on the app's canonical context.
///
/// This type is thin wiring + lifecycle over those two units. On a DB save it does BOTH: rebuild the
/// surfaces AND re-arm the boundary timer, because `nextStageRefreshTime` is a pure function of the
/// commitment set — a write can change what the next boundary IS (an added commitment with an earlier
/// slot edge outdates the armed fire; deleting the commitment that owned the next edge makes the armed
/// fire stale). No debounce in v1: `refreshAll()` is idempotent, so extra fires are wasted work, not
/// incorrectness.
@MainActor
final class RefreshCoordinator {
    private let refreshAction: () async -> Void
    private let boundaryTimer: BoundaryTimer
    private let saveObserver: ModelContextSaveObserver

    /// Idempotency guard for `start()`. A SwiftUI `App`'s `init()` can run more than once over the
    /// process lifetime, and the owning instance is a process-wide singleton, so `start()` may be
    /// invoked repeatedly. Only the first call arms the timer and registers the observer.
    private var didStart = false

    /// - Parameters:
    ///   - arm: the boundary timer's scheduling seam — schedule a fire at a date, return its
    ///     canceller. Defaults (inside `BoundaryTimer`) to a real one-shot main-run-loop `Timer`.
    ///   - nextBoundary: computes the next boundary instant. Defaults to reading active commitments
    ///     from `ModelContext.wilgoMain` and folding slot edge + cycle boundary via
    ///     `StageCharacterization.nextStageRefreshTime`.
    ///   - refreshAction: the surface rebuild. Defaults to `CommitmentChangeRefresher.refreshAll()`.
    ///   - notificationCenter: where the `didSave` observer registers. Defaults to `.default`.
    ///   - observedContext: the `ModelContext` whose `didSave` triggers a refresh + reschedule.
    ///     Defaults to `ModelContext.wilgoMain`.
    ///
    /// Defaults are resolved in the body (not as default-argument expressions) so their
    /// main-actor-isolated construction (`ModelContext.wilgoMain`) runs in this `@MainActor` init's
    /// context — `-default-isolation=MainActor` would otherwise evaluate default-arg expressions in
    /// a nonisolated context.
    init(
        arm: BoundaryTimer.Arm? = nil,
        nextBoundary: (() -> Date)? = nil,
        refreshAction: (() async -> Void)? = nil,
        notificationCenter: NotificationCenter? = nil,
        observedContext: ModelContext? = nil
    ) {
        let resolvedRefresh = refreshAction ?? { await CommitmentChangeRefresher.refreshAll() }
        let resolvedNextBoundary = nextBoundary ?? RefreshCoordinator.defaultNextBoundary
        let resolvedContext = observedContext ?? ModelContext.wilgoMain
        let resolvedCenter = notificationCenter ?? .default

        self.refreshAction = resolvedRefresh

        let timer = BoundaryTimer(
            nextBoundary: resolvedNextBoundary,
            onFire: resolvedRefresh,
            arm: arm
        )
        boundaryTimer = timer

        saveObserver = ModelContextSaveObserver(
            context: resolvedContext,
            center: resolvedCenter
        ) {
            // On a DB save, do BOTH: fire-and-forget the surface rebuild (the only async part, so the
            // saving code isn't blocked on it) AND synchronously recompute + re-arm the boundary timer
            // (the next boundary is a pure function of the commitment set the save just changed).
            Task { await resolvedRefresh() }
            timer.schedule()  // Re-schedule the timer!!!!!
        }
    }

    /// Begin waking at time boundaries and reacting to DB writes. Arms the timer to the first
    /// computed boundary and registers the `didSave` observer.
    ///
    /// Idempotent: a second `start()` is a no-op, so repeated calls (e.g. a SwiftUI `App` whose
    /// `init()` runs more than once) never arm overlapping timers or double-register the observer.
    func start() {
        guard !didStart else { return }
        didStart = true
        boundaryTimer.schedule()
        saveObserver.start()
    }

    /// Stop waking at time boundaries and reacting to DB writes.
    func stop() {
        boundaryTimer.cancel()
        saveObserver.stop()
    }

    /// Production `nextBoundary`: fold the next slot edge and next cycle boundary over the app's
    /// active commitments. Mirrors `NowLiveActivityManager.nextWakeEarliestDate`.
    static func defaultNextBoundary() -> Date {
        let now = Time.now()
        let commitments = (try? ModelContext.wilgoMain.fetch(.activeOnly)) ?? []
        return StageCharacterization.nextStageRefreshTime(commitments: commitments, now: now)
    }
}
