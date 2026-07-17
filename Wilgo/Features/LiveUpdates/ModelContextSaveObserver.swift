import Foundation
import SwiftData

/// Generic, Wilgo-agnostic seam that watches a single `ModelContext` for `ModelContext.didSave`
/// and runs a closure on each save. It knows nothing about timers, refreshes, or boundaries — its
/// only job is "context saved → run `onSave`".
///
/// Object-scoped: SwiftData posts the saving `ModelContext` as the notification's `object`, so we
/// register with `object: context` and only react to writes on the exact context we were given
/// (a save on a different context is ignored).
///
/// Threading: SwiftData posts `didSave` synchronously on the saving thread. The observed context
/// is expected to be a main-actor `ModelContext` saved on the main actor, so the handler is already
/// on the main actor — `MainActor.assumeIsolated` lets `onSave` run synchronously in that context.
@MainActor
final class ModelContextSaveObserver {
    private let context: ModelContext
    private let center: NotificationCenter
    private let onSave: () -> Void

    /// Token for the registered observer, retained so `stop()`/`deinit` can remove it. Non-nil
    /// exactly when the observer is registered — doubles as the idempotency guard for `start()`.
    private var observer: NSObjectProtocol?

    /// - Parameters:
    ///   - context: the `ModelContext` whose `didSave` triggers `onSave`.
    ///   - center: where the observer registers. Defaults to `.default` (nonisolated, safe as a
    ///     default-argument expression under `-default-isolation=MainActor`).
    ///   - onSave: run on the main actor, synchronously, on each save of `context`.
    init(
        context: ModelContext,
        center: NotificationCenter = .default,
        onSave: @escaping () -> Void
    ) {
        self.context = context
        self.center = center
        self.onSave = onSave
    }

    deinit {
        if let observer {
            center.removeObserver(observer)
        }
    }

    /// Register the `didSave` observer, scoped to `context`. Idempotent: a second `start()` while
    /// already registered is a no-op, so `onSave` never double-fires from one save.
    func start() {
        guard observer == nil else { return }
        observer = center.addObserver(
            forName: ModelContext.didSave,
            object: context,
            queue: nil
        ) { [weak self] _ in
            // SwiftData posts `didSave` synchronously on the saving thread; the observed context is
            // a main-actor context saved on the main actor, so we are already on the main actor.
            // `assumeIsolated` lets `onSave` run synchronously here.
            MainActor.assumeIsolated {
                self?.onSave()
            }
        }
    }

    /// Remove the observer. After `stop()`, a later save on `context` no longer runs `onSave`.
    func stop() {
        if let observer {
            center.removeObserver(observer)
            self.observer = nil
        }
    }
}
