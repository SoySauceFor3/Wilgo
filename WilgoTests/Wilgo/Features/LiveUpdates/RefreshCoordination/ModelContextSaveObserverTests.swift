import Foundation
import SwiftData
import Testing
@testable import Wilgo

extension LiveUpdatesSuite.RefreshCoordinationSuite {
@Suite(.serialized)
@MainActor
final class ModelContextSaveObserverTests {
    // MARK: - Helpers

    private func makeCommitment(in ctx: ModelContext) -> Commitment {
        let c = Commitment(
            title: "Test",
            cycle: Cycle(kind: .daily, referencePsychDay: Date()),
            slots: [],
            target: Target(count: 1)
        )
        ctx.insert(c)
        return c
    }

    /// Yield the cooperative pool until `predicate` holds or we exhaust `maxYields`. Used to let a
    /// detached fire-and-forget `Task` run before asserting — no `Thread.sleep`.
    private func waitUntil(
        maxYields: Int = 100,
        _ predicate: () -> Bool
    ) async {
        var yields = 0
        while !predicate(), yields < maxYields {
            await Task.yield()  // Pause me here, let the scheduler run any other pending tasks, then resume me.
            yields += 1
        }
    }

    // MARK: - Tests

    @Test("a real save() on the observed context runs onSave")
    func save_runsOnSave() async throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        var saveCount = 0
        let observer = ModelContextSaveObserver(context: ctx) { saveCount += 1 }
        observer.start()

        _ = makeCommitment(in: ctx)
        try ctx.save()

        await waitUntil { saveCount == 1 }
        #expect(saveCount == 1)
    }

    @Test("a save on a DIFFERENT context does NOT run onSave")
    func save_onOtherContext_doesNotRun() async throws {
        let observedContainer = try makeTestContainer()
        let observedCtx = observedContainer.mainContext
        let otherContainer = try makeTestContainer()
        let otherCtx = ModelContext(otherContainer)
        var saveCount = 0
        let observer = ModelContextSaveObserver(context: observedCtx) { saveCount += 1 }
        observer.start()

        _ = makeCommitment(in: otherCtx)
        try otherCtx.save()

        await waitUntil(maxYields: 20) { saveCount > 0 }
        #expect(saveCount == 0)
    }

    @Test("stop() removes the observer: a later save does not run onSave")
    func stop_removesObserver() async throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        var saveCount = 0
        let observer = ModelContextSaveObserver(context: ctx) { saveCount += 1 }
        observer.start()
        observer.stop()

        _ = makeCommitment(in: ctx)
        try ctx.save()

        await waitUntil(maxYields: 20) { saveCount > 0 }
        #expect(saveCount == 0)
    }

    @Test("letting the observer deinit removes it: a later save does not run onSave")
    func deinit_removesObserver() async throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        var saveCount = 0
        do {
            let observer = ModelContextSaveObserver(context: ctx) { saveCount += 1 }
            observer.start()
        }
        // `observer` is out of scope and deallocated here; its deinit must have removed the observer.

        _ = makeCommitment(in: ctx)
        try ctx.save()

        await waitUntil(maxYields: 20) { saveCount > 0 }
        #expect(saveCount == 0)
    }

    @Test(
        "start() is idempotent — a second start() does not double-register (one save → one onSave)")
    func start_isIdempotent() async throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        var saveCount = 0
        let observer = ModelContextSaveObserver(context: ctx) { saveCount += 1 }
        observer.start()
        observer.start()

        _ = makeCommitment(in: ctx)
        try ctx.save()

        await waitUntil { saveCount == 1 }
        // Give any errant second registration a chance to fire; the count must stay exactly 1.
        await waitUntil(maxYields: 20) { saveCount > 1 }
        #expect(saveCount == 1)
    }

    @Test("N distinct saves run onSave N times (no coalescing/debounce)")
    func multipleSaves_runOnSaveEachTime() async throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        var saveCount = 0
        let observer = ModelContextSaveObserver(context: ctx) { saveCount += 1 }
        observer.start()

        let saveTarget = 3
        for expected in 1...saveTarget {
            _ = makeCommitment(in: ctx)
            try ctx.save()
            // Wait for THIS save's onSave before issuing the next, so each is a distinct didSave
            // post rather than one notification coalesced across several inserts.
            await waitUntil { saveCount == expected }
            #expect(saveCount == expected)
        }

        #expect(saveCount == saveTarget)
    }
}
}
