import ActivityKit
import Foundation
import SwiftData

enum NowLiveActivityManager: BackgroundRefreshScheduler {
    @MainActor
    private static var refreshTask: Task<Void, Never>?

    // Serializes runs so no `refresh()` body starts until the previous one has fully finished —
    // `refresh()` breaks if two runs interleave (see its doc). Two pieces do this:
    //
    // 1. The Task bridges sync callers into async `refresh()`, AND its handle reifies the
    //    in-flight run as a value the next call can wait on. (A bare `await refresh()`
    //    would leave nothing for the next call to chain behind.)
    // 2. The read of `previous` and the write of `refreshTask` are synchronous and adjacent —
    //    no `await` between them — so the swap is an atomic "append myself to the chain" step.
    //    A later `apply()` is therefore guaranteed to read THIS run as its `previous`; it can't
    //    slip into a gap and chain behind the wrong predecessor.
    @MainActor
    private static func apply() {
        let previous = refreshTask

        // Scheduling note: `Task { ... }` constructs the task and returns its handle synchronously,
        // so the assignment to `refreshTask` completes before the body runs. The body itself is only
        // ENQUEUED on the main actor's executor, not run inline — because `apply()` is synchronous
        // and already on the main actor, the body can't start until the current synchronous work
        // unwinds and the executor is free. Correctness does not depend on WHEN the body starts,
        // only on the synchronous read/write in point 2: whenever the body runs, `previous` has
        // already captured the prior task by value, so `await previous?.value` gates behind it.
        refreshTask = Task { @MainActor in
            // Gate: park this run until the previous run's `refresh()` has fully returned (including
            // all of its internal `await`s), so their bodies never interleave.
            await previous?.value
            await LiveActivityRefresher.refresh(context: ModelContext.wilgoMain)
        }
    }

    static let backgroundTaskIdentifier = "wilgo.live-activity-sync"

    /// Wake at the next slot edge OR cycle boundary (folded together by `nextStageRefreshTime`), so
    /// the app also refreshes at the daily-cycle rollover when no slot transition precedes it.
    @MainActor
    static var nextWakeEarliestDate: Date {
        let now = Time.now()
        let commitments = (try? ModelContext.wilgoMain.fetch(.activeOnly)) ?? []
        return StageCharacterization.nextStageRefreshTime(commitments: commitments, now: now)
    }

    /// Chains a reconcile behind any in-flight one and awaits it (see `apply()` for why runs
    /// must not interleave).
    @MainActor
    static func performWork() async {
        apply()
        // `refreshTask` is read synchronously right after `apply()` on the main actor, so it is
        // exactly the run just chained — no later `apply()` can swap the chain head in between.
        await refreshTask?.value
    }
}
