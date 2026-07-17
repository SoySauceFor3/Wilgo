import Foundation

/// THE background-wake pattern for the notification schedulers. Each conformer owns one
/// BGAppRefreshTask and one reconcile, wired together by the defaults below — a conformer
/// declares only its identifier, its wake policy, and its work.
///
/// Lifecycle (identical for every conformer):
/// 1. `WilgoApp.init` calls `registerBackgroundTask()` — must run before any submit.
/// 2. `refresh()` is the only entry point anyone calls (scene-phase handler, BG fire, and
///    `CommitmentChangeRefresher.refreshAll` — driven by `RefreshCoordinator`'s boundary
///    timer and DB-save observer). It re-queues the next wake FIRST — so a mid-flight kill
///    still leaves a wake queued — then runs `performWork()`. That ordering is the
///    template's load-bearing invariant: re-queue BEFORE work, never after.
/// 3. `BGWake` completes the BGTask only after `refresh()` returns (returning means the
///    work is done) and reports failure on expiration so iOS retries.
/// 4. iOS treats `earliestBeginDate` as a floor, not a promise — BG fires are
///    best-effort. The scene-phase calls double as the watchdog that re-queues wakes
///    whenever iOS skipped one.
///
/// `CycleEndNotificationScheduler` deliberately does NOT conform: it schedules repeating
/// calendar triggers and needs no background wake.
protocol BackgroundRefreshScheduler {
    static var backgroundTaskIdentifier: String { get }
    /// Wake policy: the earliest instant iOS may launch us next.
    @MainActor static var nextWakeEarliestDate: Date { get }
    /// The reconcile itself. Returning means the work is done (BGWake awaits this).
    ///
    /// DO NOT call directly — go through `refresh()`. Calling `performWork()` standalone runs
    /// the reconcile WITHOUT re-queuing the next wake, silently defeating the crash-safety
    /// invariant (item 2 above). It is a protocol requirement only because conformers must
    /// supply it; it is not a public entry point.
    @MainActor static func performWork() async
}

extension BackgroundRefreshScheduler {
    /// Register the BGAppRefreshTask handler. Must be called before any submit — i.e., from
    /// `WilgoApp.init`.
    static func registerBackgroundTask() {
        BGWake.register(backgroundTaskIdentifier) { await refresh() }
    }

    /// Submit (or replace) the next wake per `nextWakeEarliestDate`.
    @MainActor
    static func scheduleBackgroundTask() {
        BGWake.submit(backgroundTaskIdentifier, earliestBeginDate: nextWakeEarliestDate)
    }

    /// The single entry point: re-queue the next wake FIRST (mid-flight kill still leaves
    /// a wake queued), then reconcile.
    ///
    /// This is a protocol-extension default, so Swift does NOT seal it — a conformer that
    /// declares its own `refresh()` would silently shadow this and could drop the re-queue.
    /// Don't override it in a conformer; the whole template depends on this exact ordering.
    @MainActor
    static func refresh() async {
        scheduleBackgroundTask()
        await performWork()
    }
}
