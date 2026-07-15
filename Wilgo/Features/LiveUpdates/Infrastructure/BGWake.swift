import BackgroundTasks
import Foundation
import OSLog

/// Seam so `BGWake.handle`'s completion-race logic is unit-testable: a real `BGTask`
/// cannot be instantiated, and `BGTaskScheduler.register` only accepts Info.plist-declared
/// identifiers once per process.
protocol BGWakeTask: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

extension BGTask: BGWakeTask {}

/// One home for the BGAppRefreshTask boilerplate shared by the schedulers in
/// `Features/LiveUpdates`: registration (a completion-race-safe launch handler with an
/// expiration handler) and submission (replace-in-place, failures logged instead of swallowed).
enum BGWake {
    /// Persisted diagnostics, same rationale as `LiveActivityRefresher.logger`: dogfood runs
    /// are unattached; `.notice` entries survive in the system log store (filter subsystem
    /// "wilgo" in Console.app / `log collect`).
    private static let logger = Logger(subsystem: "wilgo", category: "BGWake")

    /// Register `work` as the launch handler for `identifier`.
    /// Must be called before any `submit` for the same identifier — i.e., from `App.init`.
    static func register(_ identifier: String, work: @escaping @MainActor () async -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handle(task, work: work)
        }
    }

    /// Runs `work`, and only then reports completion: `setTaskCompleted` lets iOS suspend the
    /// process, so reporting before the work finishes would let it be killed mid-flight.
    /// If iOS reclaims the wake first (`expirationHandler` — a background wake has a limited
    /// runtime budget, roughly up to 30s for an app-refresh task, sometimes less), the work is
    /// cancelled and the task reported failed so it is retried rather than silently marked done.
    ///
    /// Returns the work `Task` so tests can await the outcome; production callers ignore it.
    @discardableResult
    static func handle(
        _ task: some BGWakeTask, work: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        let workTask = Task { @MainActor in
            await work()
            guard !Task.isCancelled else { return }  // if the task is cancelled (before expiration), check cancelled cooperatively to avoid `task.setTaskCompleted()` twice, which is a violation of the API.
            task.setTaskCompleted(success: true)
        }
        // task.expirationHandler is BGTask API's deadline callback. A background wake comes
        // with a limited runtime budget (roughly up to 30 seconds for an app-refresh task,
        // sometimes less under memory/battery pressure). If your work is still running when
        // the budget expires, iOS calls your expirationHandler as a final warning.
        task.expirationHandler = {
            workTask.cancel()
            task.setTaskCompleted(success: false)
        }
        return workTask
    }

    /// Submit (or replace — BGTaskScheduler keeps one pending request per identifier) an
    /// app-refresh wake no earlier than `earliestBeginDate`.
    static func submit(_ identifier: String, earliestBeginDate: Date?) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // `tooManyPendingTaskRequests` / `notPermitted` are exactly what explains a
            // "the BG task never fired" dogfood mystery — worth a persisted trace, never
            // worth aborting a scheduling pass (app-alive paths already did their work).
            logger.notice(
                "submit(\(identifier, privacy: .public)) failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
