import Foundation

/// Caches the three Stage lists (current / upcoming / catchUp) so that
/// `StageView.body` never recomputes them directly.
///
/// ## Refresh triggers
/// - **Model change**: `StageView` calls `refresh(commitments:)` whenever the
///   `@Query` for commitments or checkIns fires (insert / delete / update).
/// - **Time boundary**: internally schedules a `Task` that wakes exactly at the
///   next slot-boundary transition and recomputes without waiting for a model
///   change.  Replaces the old `rewrite` toggle + `.task(id: rewrite)` loop in
///   `StageView`.
@MainActor
@Observable
final class StageViewModel {
    private(set) var current: [CommitmentAndSlot.WithBehind] = []
    private(set) var upcoming: [CommitmentAndSlot.WithBehind] = []
    private(set) var catchUp: [CommitmentAndSlot.WithBehind] = []

    private var lastCommitments: [Commitment] = []
    @ObservationIgnored
    nonisolated(unsafe) private var timerTask: Task<Void, Never>?

    /// Recomputes all three lists from `commitments` and reschedules the
    /// internal timer to fire at the next slot-boundary transition.
    func refresh(commitments: [Commitment]) {
        MemoryProbe.log("Stage.refresh", extra: "commitments=\(commitments.count)")
        lastCommitments = commitments
        MemoryProbe.measure("Stage.recompute") { recompute() }
        scheduleTimer()
    }

    // MARK: - Private

    private func recompute() {
        let now = Date()
        let remindersOn = lastCommitments.filter { $0.isRemindersEnabled }
        current = CommitmentAndSlot.currentWithBehind(commitments: remindersOn, now: now)
        upcoming = CommitmentAndSlot.upcomingWithBehind(commitments: remindersOn, after: now)
        catchUp = CommitmentAndSlot.catchUpWithBehind(commitments: remindersOn, now: now)
    }

    private func scheduleTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            guard let self else { return }
            let nextDate = CommitmentAndSlot.nextTransitionDate(
                commitments: self.lastCommitments, now: Date())
            let delay = nextDate?.timeIntervalSince(Date()) ?? 60
            if delay > 0 {
                try? await Task.sleep(until: .now + .seconds(delay), clock: .continuous)
            }
            guard !Task.isCancelled else { return }
            self.recompute()
            self.scheduleTimer()
        }
    }

    deinit {
        timerTask?.cancel()
    }
}
