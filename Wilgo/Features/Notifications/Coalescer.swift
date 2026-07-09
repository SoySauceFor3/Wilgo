import Foundation

/// Serializes an async operation and *coalesces* concurrent requests: while a run is in flight,
/// any number of `trigger()` calls collapse into a single follow-up run once the current one
/// finishes.
///
/// This suits "reconcile to current state" work (e.g. `LiveActivityRefresher.refresh`), where
/// replaying every intermediate request is wasteful — the only run that matters is one that
/// observes the *latest* state. Compare with a FIFO Task-chain, which runs the operation once per
/// request; coalescing runs it at most twice for any burst (the in-flight run plus one rerun that
/// sees the final state).
///
/// # Why the rerun can't be dropped
/// The subtle bug in hand-rolled versions: a `trigger()` lands in the tiny window while the current
/// run is finishing, but after the loop already decided not to rerun — so the request is silently
/// lost. `Coalescer` avoids this by only ever *setting* `needsRerun` from `trigger()`, and
/// clearing-then-re-checking it around each run entirely on the main actor with no `await` between
/// the clear and the run's start. Any trigger that arrives during the run's suspension is therefore
/// guaranteed to be observed by the `while needsRerun` check.
///
/// All state is `@MainActor`-isolated, so the flag reads/writes are free of data races and the
/// clear/check happen without interleaving.
@MainActor
final class Coalescer {
    private let operation: () async -> Void
    private var isRunning = false
    private var needsRerun = false
    /// The task driving the current run-loop, if any. `wait()` awaits it; a fresh `trigger()`
    /// after quiescence replaces it.
    private var runLoop: Task<Void, Never>?

    init(operation: @escaping () async -> Void) {
        self.operation = operation
    }

    /// Request a run. If one is already in flight, fold into a single pending rerun instead of
    /// starting a second run. Synchronous and non-blocking — callers never wait here.
    func trigger() {
        guard !isRunning else {
            needsRerun = true
            return
        }
        isRunning = true
        runLoop = Task { @MainActor in
            repeat {
                // Clear BEFORE the run so a trigger arriving *during* the run is not lost: it will
                // set needsRerun back to true and be caught by the while check below. No `await`
                // between this clear and `operation()` starting, so the window is closed.
                needsRerun = false
                await operation()
            } while needsRerun
            isRunning = false
        }
    }

    /// Await completion of any in-flight run and any rerun it spawns. Returns immediately if idle.
    /// A request absorbed into an already-running run has no distinct handle; awaiting the run-loop
    /// still guarantees that a run observing state at-or-after the caller's `trigger()` has
    /// completed by the time this returns.
    func wait() async {
        await runLoop?.value
    }
}
