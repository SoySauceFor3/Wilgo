import ActivityKit
import Foundation
import OSLog

/// Standalone experiment: does `activity.update(content:)` mutate a Live Activity that is still
/// `.pending` (scheduled to start in the future), or does it silently no-op?
///
/// This convicts or clears the assumption baked into `LiveActivityRefresher.updateStartedCards`,
/// which calls `.update()` on seated cards. If `.update()` no-ops on `.pending` cards, edits made
/// before a scheduled card fires would be lost.
///
/// Runs once right after app start, with no UI, ONLY in the `PENDING_UPDATE_PROBE` build. In that
/// build `NowLiveActivityManager.apply()` is suppressed, so this probe's card is the only Live
/// Activity in play and nothing ends it as an orphan before it fires.
///
/// The proof is the log trail (subsystem "wilgo", category "LiveActivityProbe") plus one manual
/// eye-check: ~90s after launch the scheduled card appears. If it reads "PROBE-AFTER …" then
/// `update()` on a pending card works; if it reads "PROBE-BEFORE …" it silently no-ops.
enum PendingUpdateProbe {
    private static let logger = Logger(subsystem: "wilgo", category: "LiveActivityProbe")
    private static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    @MainActor
    static func run() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log("SKIP: Live Activities are disabled for this app in Settings.")
            return
        }

        let now = Date()
        let windowStart = now.addingTimeInterval(90)  // card fires ~90s after launch
        let windowEnd = now.addingTimeInterval(3600)

        let before = state(title: "PROBE-BEFORE \(timeFormatter.string(from: now))",
                           windowStart: windowStart, windowEnd: windowEnd)

        let activity: Activity<NowAttributes>
        do {
            activity = try Activity.request(
                attributes: NowAttributes(),
                content: ActivityContent(state: before, staleDate: nil),
                pushType: nil,
                style: .standard,
                alertConfiguration: AlertConfiguration(
                    title: "Update probe",
                    body: "scheduled card",
                    sound: .default
                ),
                start: windowStart
            )
        } catch {
            log("FAIL: scheduled request threw: \(error)")
            return
        }
        log("requested id=\(String(activity.id.prefix(8))) state=\(activity.activityState) title=\(before.commitmentTitle)")

        // Wait a moment — still well before windowStart, so the card must still be .pending.
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        log("before update: id=\(String(activity.id.prefix(8))) state=\(activity.activityState) (expect pending)")

        let afterTime = Date()
        let after = state(title: "PROBE-AFTER \(timeFormatter.string(from: afterTime))",
                          windowStart: windowStart, windowEnd: windowEnd)
        // NOTE: `activity.update(_:)` is async but NOT throwing in this ActivityKit SDK — it returns
        // void and gives no failure signal. So "it returned" proves nothing about whether the
        // content actually changed; only the eye-check of the fired card can prove that.
        await activity.update(ActivityContent(state: after, staleDate: nil))
        log("update() returned — content requested = \(after.commitmentTitle)")
        log("after update: id=\(String(activity.id.prefix(8))) state=\(activity.activityState)")
        log("NOW WATCH: at ~\(timeFormatter.string(from: windowStart)) the card should fire. "
            + "If it reads PROBE-AFTER, update() on pending WORKS. If PROBE-BEFORE, it silently no-ops.")
    }

    private static func state(title: String, windowStart: Date, windowEnd: Date)
        -> NowAttributes.ContentState
    {
        NowAttributes.ContentState(
            commitmentTitle: title,
            slotTimeText: "\(timeFormatter.string(from: windowStart)) – \(timeFormatter.string(from: windowEnd))",
            commitmentId: UUID(),
            slotId: UUID(),
            windowStart: windowStart,
            windowEnd: windowEnd,
            encouragementText: nil,
            checkInCount: nil,
            targetCount: nil
        )
    }
}
