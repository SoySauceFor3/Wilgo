import Foundation

@MainActor
private var nextStageViewModelInstanceID = 0

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

    private let instanceID: Int
    private var lastCommitments: [Commitment] = []
    @ObservationIgnored
    nonisolated(unsafe) private var timerTask: Task<Void, Never>?

    var debugID: Int { instanceID }

    init() {
        nextStageViewModelInstanceID += 1
        instanceID = nextStageViewModelInstanceID
        MemoryProbe.log("StageViewModel.init", extra: "vm=\(instanceID)")
    }

    /// Recomputes all three lists from `commitments` and reschedules the
    /// internal timer to fire at the next slot-boundary transition.
    func refresh(commitments: [Commitment]) {
        MemoryProbe.log(
            "Stage.refresh",
            extra: "vm=\(instanceID) commitments=\(commitments.count)"
        )
        lastCommitments = commitments
        MemoryProbe.measure("Stage.recompute") { recompute() }
        MemoryProbe.log(
            "Stage.recompute.output",
            extra: "vm=\(instanceID) current=\(current.count) upcoming=\(upcoming.count) catchUp=\(catchUp.count)"
        )
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
        let nextDate = CommitmentAndSlot.nextTransitionDate(
            commitments: lastCommitments, now: Date())
        let delay = nextDate?.timeIntervalSince(Date()) ?? 60
        MemoryProbe.log(
            "Stage.timer.schedule",
            extra: "vm=\(instanceID) delay=\(String(format: "%.1f", delay))s"
        )
        timerTask = Task { [weak self, delay, instanceID] in
            if delay > 0 {
                try? await Task.sleep(until: .now + .seconds(delay), clock: .continuous)
            }
            guard !Task.isCancelled else {
                MemoryProbe.log("Stage.timer.cancelled", extra: "vm=\(instanceID)")
                return
            }
            guard let self else { return }
            MemoryProbe.log("Stage.timer.fire", extra: "vm=\(instanceID)")
            self.recompute()
            self.scheduleTimer()
        }
    }

    deinit {
        MemoryProbe.log("StageViewModel.deinit", extra: "vm=\(instanceID)")
        timerTask?.cancel()
    }
}
