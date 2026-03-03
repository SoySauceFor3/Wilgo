import ActivityKit
import Foundation
import SwiftData

/// Owns all Live Activity lifecycle operations (start / update / end).
///
/// ## How it stays in sync
///
/// Two complementary mechanisms keep the live activity correct whenever the app
/// process is running — regardless of which tab is visible:
///
/// 1. **Monitoring loop** (`startMonitoring`): wakes at each slot boundary
///    (window open / window close) and syncs automatically. Runs for the full
///    lifetime of this object, which is the full lifetime of the app.
///
/// 2. **Explicit `sync()` calls**: for changes that don't involve a time
///    boundary — a user completing a habit, adding a snooze, etc. — callers
///    invoke `sync()` directly so the activity updates immediately without
///    waiting for the next boundary wake-up.
///
/// When the app is terminated, neither mechanism runs. That case requires push
/// notifications (ActivityKit push type). The `staleDate` passed to every
/// `ActivityContent` provides graceful degradation: iOS marks the activity
/// stale when the slot window closes.
@MainActor
@Observable
final class LiveActivityManager {
    private let modelContext: ModelContext
    @ObservationIgnored
    nonisolated(unsafe) private var monitoringTask: Task<Void, Never>?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        startMonitoring()
    }

    deinit {
        monitoringTask?.cancel()
    }

    // MARK: - Public

    /// Immediately syncs the live activity to the current state.
    ///
    /// Call this whenever habit data changes while the app is on screen.
    /// (Calling it on `scenePhase == .active` is not necessary because the monitoring loop already runs in the background, but just a cheap safety net.)
    func sync() {
        let state = currentState()
        Task {  // The reason it wraps apply in a Task {} is that apply is async (it calls into ActivityKit, which is asynchronous), but sync() itself is not async
            await apply(
                contentState: state.firstLiveActivityContentState,
                staleDate: state.firstLiveActivityStaleDate)
        }
    }

    // MARK: - Monitoring loop

    /// Starts (or restarts) the internal loop that wakes at each slot boundary
    /// and syncs the live activity without any view needing to be on screen.
    private func startMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = Task {
            while !Task.isCancelled {
                let state = self.currentState()
                await self.apply(
                    contentState: state.firstLiveActivityContentState,
                    staleDate: state.firstLiveActivityStaleDate)

                let delay = max(state.nextTransitionDate.timeIntervalSince(Date()), 1)  // ensures we never sleep for 0 or negative seconds
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    // MARK: - Helpers

    private func currentState() -> StageState {
        let habits = (try? modelContext.fetch(FetchDescriptor<Habit>())) ?? []
        let snoozedSlots = (try? modelContext.fetch(FetchDescriptor<SnoozedSlot>())) ?? []
        return StageEngine.makeState(habits: habits, snoozedSlots: snoozedSlots, now: Date())
    }

    // takes the computed state and tells iOS what to actually show (or not show) on the Lock Screen.
    private func apply(contentState: NowAttributes.ContentState?, staleDate: Date?) async {
        if let state = contentState, state.hasCurrentHabit {
            let content = ActivityContent(state: state, staleDate: staleDate)
            if let activity = Activity<NowAttributes>.activities.first {
                await activity.update(content)
            } else {
                _ = try? Activity.request(
                    attributes: NowAttributes(),
                    content: content,
                    pushType: nil
                )
            }
        } else {
            for activity in Activity<NowAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
