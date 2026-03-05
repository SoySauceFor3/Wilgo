import BackgroundTasks
import Foundation
import SwiftData
import UserNotifications

/// Delivers the "morning report" notification by waking the app at 8 AM via BGAppRefreshTask.
///
/// ## Flow
/// 1. `scheduleBackgroundTask()` — called on every app-active. Submits (or replaces)
///    a BGAppRefreshTask targeting 8 AM today (or tomorrow if 8 AM has passed).
///
/// 2. **BGAppRefreshTask fires at 8 AM** (background, no app open needed):
///    `handleBackgroundTask(for:)` computes yesterday's miss data, posts notifications
///    immediately, then re-schedules itself for the next 8 AM. Self-sustaining loop. -- are we really doing this itself?
///
/// 3. If the user opens the app instead of relying on the notification, the Stage view
///    shows the live credit state directly — no separate notification needed.
enum MorningReportService {

    static let defaultDayStartHour = 8
    static let backgroundTaskIdentifier = "wilgo.morning-report-scheduler"

    // MARK: - Public

    /// Queue the 8 AM background wakeup. Safe to call on every app-active event.
    static func scheduleBackgroundTask(
        dayStartHour: Int = defaultDayStartHour,
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
    static func handleBackgroundTask(
        for habits: [Habit],
        dayStartHour: Int = defaultDayStartHour,
        now: Date = .now
    ) {
        postNotifications(for: habits, now: now)
        scheduleBackgroundTask(dayStartHour: dayStartHour, now: now)
    }

    // MARK: - Private

    /// Builds the notification content for a habit that was missed on `missedDay`.
    /// Credit state and period label are computed relative to `missedDay` so they always
    /// reflect the period the miss actually occurred in (avoids period-boundary confusion).
    /// Exposed internally so it can be unit-tested without touching UNUserNotificationCenter.
    static func notificationContent(for habit: Habit, missedDay: Date)
        -> UNMutableNotificationContent
    {
        let used = SkipCreditService.creditsUsed(for: habit, now: missedDay)
        let remaining = SkipCreditService.creditsRemaining(for: habit, now: missedDay)
        let label = SkipCreditService.periodLabel(for: habit, now: missedDay)
        let content = UNMutableNotificationContent()
        content.sound = .default

        if remaining == 0, let punishment = habit.punishment {
            content.title = "\(habit.title) — No Credits Left"
            content.body =
                "All \(habit.skipCreditCount) credits used (\(label)). Don't forget: \(punishment)"
        } else {
            let word = used == 1 ? "credit" : "credits"
            content.title = "\(habit.title) — Morning Report"
            content.body =
                "Missed yesterday. \(used) \(word) used this period (\(label)). \(remaining) remaining."
        }
        return content
    }

    private static func postNotifications(for habits: [Habit], now: Date) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let cal = HabitScheduling.calendar
            let today = HabitScheduling.todayPsychDay(now: now)
            let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today

            center.removePendingNotificationRequests(
                withIdentifiers: habits.map { notificationID(for: $0) })

            for habit in habits {
                // Only notify if yesterday was a miss.
                let completions = habit.checkIns.filter { $0.psychDay == yesterday }.count
                guard completions < habit.slots.count else { continue }

                let content = notificationContent(for: habit, missedDay: yesterday)

                // Deliver immediately from the background task.
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                let request = UNNotificationRequest(
                    identifier: notificationID(for: habit),
                    content: content,
                    trigger: trigger
                )
                center.add(request)
            }
        }
    }

    private static func notificationID(for habit: Habit) -> String {
        return "wilgo.morning-report.\(habit.persistentModelID.encoded())"
    }
}
