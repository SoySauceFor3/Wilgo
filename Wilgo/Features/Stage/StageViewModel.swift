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
    private(set) var upcoming: [CommitmentAndSlot.UpcomingEntry] = []
    private(set) var catchUp: [CommitmentAndSlot.WithBehind] = []

    private var lastCommitments: [Commitment] = []
    @ObservationIgnored
    private nonisolated(unsafe) var timerTask: Task<Void, Never>?

    /// Recomputes all three lists from `commitments` and reschedules the
    /// internal timer to fire at the next slot-boundary transition.
    func refresh(commitments: [Commitment]) {
        lastCommitments = commitments
        recompute()
        scheduleTimer()
    }

    // MARK: - Private

    private func recompute() {
        let now = Date()
        // stageBuckets owns the active filter + closest-N + priority/demotion rule, so all three
        // lists come from one call and stay mutually consistent.
        let buckets = CommitmentAndSlot.stageBuckets(
            commitments: lastCommitments,
            now: now,
            n: AppSettings.upcomingCommitmentCount
        )
        current = buckets.current
        upcoming = buckets.upcoming
        catchUp = buckets.catchUp
    }

    private func scheduleTimer() {
        timerTask?.cancel()
        let nextDate = CommitmentAndSlot.nextTransitionDate(
            commitments: lastCommitments, now: Date())
        let delay = nextDate?.timeIntervalSince(Date()) ?? 60
        timerTask = Task { [weak self, delay] in
            if delay > 0 {
                try? await Task.sleep(until: .now + .seconds(delay), clock: .continuous)
            }
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.recompute()
            self.scheduleTimer()
        }
    }

    deinit {
        timerTask?.cancel()
    }
}
