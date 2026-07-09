import Foundation
import Testing
@testable import Wilgo

/// Deterministic tests for `Coalescer`'s serialization + coalescing semantics.
///
/// The operation under test is a controllable async closure (gated by a continuation the test
/// resumes), so we can hold a run "in flight", fire `trigger()` any number of times while it is
/// suspended, and then observe exactly how many runs happened. No ActivityKit / store involved.
@MainActor
@Suite(.serialized)
final class CoalescerTests {
    /// A run operation that (a) counts invocations and (b) suspends on each run until the test
    /// explicitly releases it, so the test controls interleaving precisely.
    final class ControllableOp {
        private(set) var runCount = 0
        private var pending: [CheckedContinuation<Void, Never>] = []
        /// Signalled after each run has *started* (count incremented, now suspended), so the test
        /// can synchronize on "a run is in flight" without polling.
        var onStarted: (() -> Void)?

        func run() async {
            runCount += 1
            onStarted?()
            await withCheckedContinuation { pending.append($0) }
        }

        /// Release the oldest suspended run so it can complete.
        func releaseOne() {
            guard !pending.isEmpty else { return }
            pending.removeFirst().resume()
        }

        var suspendedCount: Int { pending.count }
    }

    /// Await until `condition` holds, yielding between checks. Fails the test on timeout so a
    /// broken coalescer can't hang the suite forever.
    private func waitUntil(
        _ condition: () -> Bool, _ message: String, iterations: Int = 10_000
    ) async {
        var i = 0
        while !condition(), i < iterations {
            await Task.yield()
            i += 1
        }
        #expect(condition(), "timed out waiting: \(message)")
    }

    @Test("a single trigger runs the operation exactly once")
    func singleTrigger_runsOnce() async {
        let op = ControllableOp()
        let coalescer = Coalescer { await op.run() }

        coalescer.trigger()
        await waitUntil({ op.runCount == 1 }, "first run to start")
        op.releaseOne()
        await coalescer.wait()

        #expect(op.runCount == 1)
    }

    @Test("triggers arriving during an in-flight run collapse into exactly one rerun")
    func triggersDuringRun_collapseIntoOneRerun() async {
        let op = ControllableOp()
        let coalescer = Coalescer { await op.run() }

        // Start run #1 and leave it suspended.
        coalescer.trigger()
        await waitUntil({ op.runCount == 1 }, "run #1 to start")

        // Fire several triggers while run #1 is still in flight. These must NOT each start a run;
        // they must fold into a single pending rerun.
        coalescer.trigger()
        coalescer.trigger()
        coalescer.trigger()
        #expect(op.runCount == 1, "no new run should start while one is in flight")

        // Let run #1 finish; the coalesced rerun (#2) should then start.
        op.releaseOne()
        await waitUntil({ op.runCount == 2 }, "coalesced rerun to start")
        #expect(op.runCount == 2)

        // No further reruns are queued: releasing #2 ends everything.
        op.releaseOne()
        await coalescer.wait()
        #expect(op.runCount == 2, "at most one rerun should be queued for a burst")
    }

    @Test("a trigger after quiescence starts a fresh run")
    func triggerAfterQuiescence_startsFreshRun() async {
        let op = ControllableOp()
        let coalescer = Coalescer { await op.run() }

        coalescer.trigger()
        await waitUntil({ op.runCount == 1 }, "run #1")
        op.releaseOne()
        await coalescer.wait()
        #expect(op.runCount == 1)

        // System is now idle. A new trigger must start a brand-new run, not be absorbed.
        coalescer.trigger()
        await waitUntil({ op.runCount == 2 }, "run #2 after idle")
        op.releaseOne()
        await coalescer.wait()
        #expect(op.runCount == 2)
    }

    @Test("wait() returns only after in-flight work (and any coalesced rerun) completes")
    func wait_awaitsInFlightAndRerun() async {
        let op = ControllableOp()
        let coalescer = Coalescer { await op.run() }

        coalescer.trigger()
        await waitUntil({ op.runCount == 1 }, "run #1 to start")
        coalescer.trigger()  // queue a rerun while #1 is in flight

        // Kick off a waiter; it must not complete until BOTH runs finish.
        let waiter = Task { @MainActor in await coalescer.wait() }

        op.releaseOne()  // finish #1 → rerun #2 starts (still suspended)
        await waitUntil({ op.runCount == 2 }, "rerun to start")
        #expect(!waiter.isCancelled)

        op.releaseOne()  // finish #2
        await waiter.value  // should now return
        #expect(op.runCount == 2)
    }
}
