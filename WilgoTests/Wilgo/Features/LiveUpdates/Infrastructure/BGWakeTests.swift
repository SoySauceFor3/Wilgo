import Foundation
import Testing
@testable import Wilgo

/// Drives `BGWake.handle` through the `BGWakeTask` seam — a real `BGTask` cannot be
/// instantiated in tests, and `BGTaskScheduler.register` only accepts Info.plist-declared
/// identifiers once per process.
private final class FakeBGTask: BGWakeTask {
    var expirationHandler: (() -> Void)?
    private(set) var completions: [Bool] = []
    func setTaskCompleted(success: Bool) {
        completions.append(success)
    }
}

extension LiveUpdatesSuite.InfrastructureSuite {
struct BGWakeTests {
    @Test("reports success exactly once, only after the work has completed")
    @MainActor
    func handle_reportsSuccessAfterWork() async {
        let task = FakeBGTask()
        var workDone = false
        let handle = BGWake.handle(task) {
            // Completion must not have been reported while the work is still running.
            #expect(task.completions.isEmpty)
            workDone = true
        }
        await handle.value
        #expect(workDone)
        #expect(task.completions == [true])
    }

    @Test("installs an expiration handler synchronously")
    @MainActor
    func handle_installsExpirationHandler() {
        let task = FakeBGTask()
        BGWake.handle(task) {}
        #expect(task.expirationHandler != nil)
    }

    @Test("expiration cancels the work and reports failure exactly once")
    @MainActor
    func handle_expirationReportsFailureOnce() async {
        let task = FakeBGTask()
        let handle = BGWake.handle(task) {
            // Long-running work; cancellation makes the sleep return immediately.
            try? await Task.sleep(nanoseconds: 10_000_000_000)
        }
        // iOS reclaims the wake before the work body has even started (the work Task is
        // only enqueued on the main actor, which this test occupies).
        task.expirationHandler?()
        await handle.value
        // Exactly one completion (the failure) — the cancelled work must not add a second.
        #expect(task.completions == [false])
    }
}
}
