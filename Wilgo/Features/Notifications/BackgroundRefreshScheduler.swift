import Foundation

/// THE background-wake pattern for the notification schedulers. Each conformer owns one
/// BGAppRefreshTask and one reconcile, wired together by the defaults below — a conformer
/// declares only its identifier, its wake policy, and its work.
///
/// Lifecycle (identical for every conformer):
/// 1. `WilgoApp.init` calls `registerBackgroundTask()` — must run before any submit.
/// 2. `refresh()` is the only entry point anyone calls (scene-phase handler, BG fire,
///    `CommitmentChangeRefresher.refreshAll`, CatchUp's hourly timer). It re-queues the
///    next wake FIRST — so a mid-flight kill still leaves a wake queued — then runs
///    `performWork()`. That ordering is the template's enforced invariant.
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
    @MainActor
    static func refresh() async {
        scheduleBackgroundTask()
        await performWork()
    }
}
