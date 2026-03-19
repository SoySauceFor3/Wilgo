import BackgroundTasks
import Foundation
import SwiftData
import UserNotifications

/// Delivers the "day-start report" notification by waking the app at the user's
/// configured `dayStartHourOffset` via BGAppRefreshTask.
///
/// ## Flow
/// 1. `scheduleBackgroundTask()` — called on every app-active. Submits (or replaces)
///    a BGAppRefreshTask targeting the next day-start hour (today if not yet passed,
///    otherwise tomorrow).
///
/// 2. **BGAppRefreshTask fires at the day-start hour** (background, no app open needed):
///    `handleBackgroundTask(for:)` computes yesterday's miss data, posts notifications
///    immediately, then re-schedules itself for the next day-start. Self-sustaining loop.
///
/// 3. If the user opens the app instead of relying on the notification, the Stage view
///    shows the live credit state directly — no separate notification needed.
enum DayStartReport {

    private static let backgroundTaskIdentifier = "wilgo.day-start-report-scheduler"

    // MARK: - Public
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: DayStartReport.backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let context = ModelContext(WilgoApp.sharedModelContainer)
            let commitments = (try? context.fetch(FetchDescriptor<Commitment>())) ?? []
            DayStartReport.handleBackgroundTask(for: commitments)
            refreshTask.setTaskCompleted(success: true)
        }
    }

    /// Queue the background wakeup for the next day-start hour. Safe to call on every app-active event.
    static func scheduleBackgroundTask(
        dayStartHour: Int = Time.dayStartHourOffset,
        now: Date = .now
    ) {
        let cal = Time.calendar
        var fireDate = cal.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: now) ?? now
        if fireDate <= now {
            fireDate = cal.date(byAdding: .day, value: 1, to: fireDate) ?? fireDate
        }
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = fireDate
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Called from the BGTask handler in WilgoApp: post notifications, then re-queue for tomorrow.
    private static func handleBackgroundTask(
        for commitments: [Commitment],
        dayStartHour: Int = Time.dayStartHourOffset,
        now: Date = .now
    ) {
        postNotifications(for: commitments, now: now)
        scheduleBackgroundTask(dayStartHour: dayStartHour, now: now)
    }

    private static let summaryNotificationID = "wilgo.morning-report.summary"

    /// Builds a single summary notification covering all commitments for `yesterday`.
    /// Returns `nil` if `commitments` is empty.
    /// Exposed internally for unit testing without touching UNUserNotificationCenter.
    private static func summaryNotificationContent(
        for commitments: [Commitment], missedOn yesterday: Date
    )
        -> UNMutableNotificationContent?
    {
        guard !commitments.isEmpty else { return nil }

        let missed = commitments.filter { !$0.hasMetDailyGoal(for: yesterday) }
        let done = commitments.filter { $0.hasMetDailyGoal(for: yesterday) }

        let content = UNMutableNotificationContent()
        content.sound = .default

        if missed.isEmpty {
            content.title = "Yesterday: \(commitments.count)/\(commitments.count) done 🎉"
            content.body = done.map { "✓ \($0.title)" }.joined(separator: " · ")
            return content
        }

        content.title =
            "Yesterday: \(done.count)/\(commitments.count) done · \(missed.count) missed"

        // Missed commitments sorted by urgency: punishment first, then fewest credits left.
        let sortedMissed = missed.sorted { a, b in
            let aLeft = SkipCredit.creditsRemaining(for: a, until: yesterday)
            let bLeft = SkipCredit.creditsRemaining(for: b, until: yesterday)
            let aPunished = aLeft == 0 && a.punishment != nil
            let bPunished = bLeft == 0 && b.punishment != nil
            if aPunished != bPunished { return aPunished }
            return aLeft < bLeft
        }

        var lines = sortedMissed.map { SkipCredit.notificationLine(for: $0, on: yesterday) }

        if !done.isEmpty {
            lines.append("✓ " + done.map(\.title).joined(separator: ", "))
        }

        content.body = lines.joined(separator: "\n")
        return content
    }

    private static func postNotifications(for commitments: [Commitment], now: Date) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let cal = Time.calendar
            let today = Time.psychDay(for: now)
            let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

            center.removePendingNotificationRequests(withIdentifiers: [summaryNotificationID])

            guard let content = summaryNotificationContent(for: commitments, missedOn: yesterday)
            else { return }

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: summaryNotificationID,
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }
}
