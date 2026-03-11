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
enum DayStartReportService {

    private static let backgroundTaskIdentifier = "wilgo.day-start-report-scheduler"

    // MARK: - Public
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: DayStartReportService.backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let context = ModelContext(WilgoApp.sharedModelContainer)
            let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
            DayStartReportService.handleBackgroundTask(for: habits)
            refreshTask.setTaskCompleted(success: true)
        }
    }

    /// Queue the background wakeup for the next day-start hour. Safe to call on every app-active event.
    static func scheduleBackgroundTask(
        dayStartHour: Int = HabitScheduling.dayStartHourOffset,
        now: Date = .now
    ) {
        let cal = HabitScheduling.calendar
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
        for habits: [Habit],
        dayStartHour: Int = HabitScheduling.dayStartHourOffset,
        now: Date = .now
    ) {
        postNotifications(for: habits, now: now)
        scheduleBackgroundTask(dayStartHour: dayStartHour, now: now)
    }

    private static let summaryNotificationID = "wilgo.morning-report.summary"

    /// Builds a single summary notification covering all habits for `yesterday`.
    /// Returns `nil` if `habits` is empty.
    /// Exposed internally for unit testing without touching UNUserNotificationCenter.
    private static func summaryNotificationContent(for habits: [Habit], missedOn yesterday: Date)
        -> UNMutableNotificationContent?
    {
        guard !habits.isEmpty else { return nil }

        let missed = habits.filter { !$0.hasMetDailyGoal(for: yesterday) }
        let done = habits.filter { $0.hasMetDailyGoal(for: yesterday) }

        let content = UNMutableNotificationContent()
        content.sound = .default

        if missed.isEmpty {
            content.title = "Yesterday: \(habits.count)/\(habits.count) done 🎉"
            content.body = done.map { "✓ \($0.title)" }.joined(separator: " · ")
            return content
        }

        content.title = "Yesterday: \(done.count)/\(habits.count) done · \(missed.count) missed"

        // Missed habits sorted by urgency: punishment first, then fewest credits left.
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

    private static func postNotifications(for habits: [Habit], now: Date) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let cal = HabitScheduling.calendar
            let today = HabitScheduling.psychDay(for: now)
            let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

            center.removePendingNotificationRequests(withIdentifiers: [summaryNotificationID])

            guard let content = summaryNotificationContent(for: habits, missedOn: yesterday)
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
