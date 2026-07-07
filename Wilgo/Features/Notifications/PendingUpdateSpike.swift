import ActivityKit
import Foundation

/// TEMPORARY spike: probes whether `Activity.update()` takes effect on a *pending* (scheduled,
/// not yet started) Live Activity — behavior Apple documents for neither support nor rejection.
///
/// Run: add launch argument `-pendingUpdateSpike` to the scheme and launch. The spike pauses
/// reconciles, schedules a probe card 10 minutes out titled SPIKE-OLD (start alert
/// SPIKE-ALERT-OLD), updates it to SPIKE-NEW after 3 seconds, and prints the readback. Lock the
/// device and observe at the +10-minute mark:
///   - started card shows SPIKE-NEW  → update-on-pending works for content
///   - started card shows SPIKE-OLD  → update on pending is silently ignored
///   - start alert text is expected to still say SPIKE-ALERT-OLD either way (alert is fixed at
///     request time) — note what it actually says.
/// Cleanup: relaunch WITHOUT the launch argument — reconciles resume and orphan-end the probe.
///
/// Remove this file and `LiveActivityRefresher.spikePaused` once the question is settled.
enum PendingUpdateSpike {
    @MainActor
    static func runIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("-pendingUpdateSpike") else { return }
        LiveActivityRefresher.spikePaused = true
        print("PendingUpdateSpike: reconciles paused")

        // Clear every existing Wilgo card first: a full queue (~5) would make the probe's
        // request throw on capacity, silently turning the run into a test of nothing.
        let preexisting = Activity<NowAttributes>.activities
        for activity in preexisting {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        print("PendingUpdateSpike: cleared \(preexisting.count) existing activities")

        let start = Date().addingTimeInterval(10 * 60)
        let end = start.addingTimeInterval(30 * 60)
        let oldState = NowAttributes.ContentState(
            commitmentTitle: "SPIKE-OLD",
            slotTimeText: "spike window",
            commitmentId: UUID(),
            slotId: UUID(),
            windowStart: start,
            windowEnd: end,
            encouragementText: nil,
            checkInCount: nil,
            targetCount: nil
        )

        let activity: Activity<NowAttributes>
        do {
            activity = try Activity.request(
                attributes: NowAttributes(),
                content: ActivityContent(state: oldState, staleDate: end, relevanceScore: 1000),
                pushType: nil,
                style: .standard,
                alertConfiguration: AlertConfiguration(
                    title: "SPIKE-ALERT-OLD", body: "spike start alert", sound: .default),
                start: start
            )
        } catch {
            print("PendingUpdateSpike: scheduling FAILED: \(error)")
            LiveActivityRefresher.spikePaused = false
            return
        }
        print(
            "PendingUpdateSpike: scheduled probe id=\(String(activity.id.prefix(8))) state=\(activity.activityState) title=\(activity.content.state.commitmentTitle) start=\(start)"
        )

        try? await Task.sleep(for: .seconds(3))

        var newState = oldState
        newState.commitmentTitle = "SPIKE-NEW"
        await activity.update(
            ActivityContent(state: newState, staleDate: end, relevanceScore: 1000))
        print("PendingUpdateSpike: update() called on pending activity")

        try? await Task.sleep(for: .seconds(1))
        for probe in Activity<NowAttributes>.activities where probe.id == activity.id {
            print(
                "PendingUpdateSpike: readback state=\(probe.activityState) title=\(probe.content.state.commitmentTitle)"
            )
        }
        print(
            "PendingUpdateSpike: now lock the device; at \(start) observe the card title (SPIKE-NEW = update worked, SPIKE-OLD = ignored) and the alert text. Relaunch without -pendingUpdateSpike to clean up."
        )
    }
}
