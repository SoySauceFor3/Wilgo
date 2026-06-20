import BackgroundTasks
import Foundation
import SwiftData
import UserNotifications

enum SlotStartNotificationScheduler {
    static let backgroundTaskIdentifier = "wilgo.slot-start-scheduler"
    static let notificationIdentifierPrefix = "wilgo.slot-start."
    static let maxPendingCount = 48
    // Upper bound on how far ahead to enumerate slot starts. Without this, a user
    // with 1 slot/month would enumerate years of future dates before hitting the 48-cap.
    // And that might cause prolonged time of computation or even forever loop when trying to fulfill 48-cap.
    // 14 days is wide enough for the near future and cheap to compute.
    static let horizonDays = 14

    // MARK: - Public entry point
    @MainActor
    static func refresh(now: Date = Time.now()) {
        let context = WilgoApp.sharedModelContainer.mainContext
        let commitments = (try? context.fetch(.activeOnly)) ?? []

        let grouped = startTimeInRangeToCommitments(for: commitments, from: now)
        let requests = grouped.keys.sorted().prefix(maxPendingCount).compactMap {
            date -> UNNotificationRequest? in
            guard let cs = grouped[date] else { return nil }
            return makeRequest(for: cs, at: date)
        }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.getPendingNotificationRequests { pending in
                let oldIDs = pending.map(\.identifier)
                    .filter { $0.hasPrefix(notificationIdentifierPrefix) }
                center.removePendingNotificationRequests(withIdentifiers: oldIDs)  // remove old ones
                for request in requests {
                    center.add(request)
                }  // add new ones
            }
        }
    }

    // MARK: - BGAppRefreshTask

    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                refresh()
                scheduleBackgroundTask()
                refreshTask.setTaskCompleted(success: true)
            }
        }
    }

    static func scheduleBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(24 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Scheduling logic (internal for testing)

    /// Groups commitments by their upcoming slot-start fire dates in `(now, horizon)`.
    /// Skips any commitment whose goal is already met. Capped at `maxPendingCount` entries.
    static func startTimeInRangeToCommitments(
        for commitments: [Commitment],
        from now: Date,
        horizon: Date? = nil
    ) -> [Date: [Commitment]] {
        let horizon =
            horizon ?? Time.calendar.date(
                byAdding: .day, value: horizonDays, to: now) ?? now

        var result: [Date: [Commitment]] = [:]
        for commitment in commitments {
            guard commitment.isRemindersEnabled else { continue }
            // Same goal-met∕continue rule used by the *WithBehind helpers and Stage.
            guard commitment.isActiveForReminders(now: now) else { continue }
            for fireDate in commitment.slotStarts(from: now, to: horizon) {
                result[fireDate, default: []].append(commitment)
            }
        }
        // Enforce cap: keep only the earliest maxPendingCount fire dates
        if result.count > maxPendingCount {
            let kept = result.keys.sorted().prefix(maxPendingCount)
            result = result.filter { kept.contains($0.key) }
        }
        return result
    }

    /// Builds a `UNNotificationRequest` for the given commitments firing at `fireDate`.
    static func makeRequest(for commitments: [Commitment], at fireDate: Date)
        -> UNNotificationRequest
    {
        let content: UNMutableNotificationContent
        if commitments.count == 1, let c = commitments.first {
            content = makeSingleContent(commitment: c, fireDate: fireDate)
        } else {
            content = makeMultiContent(commitments: commitments)
        }
        content.sound = .default

        let identifier =
            notificationIdentifierPrefix + ISO8601DateFormatter().string(from: fireDate)
        let components = Time.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    // MARK: - Content builders

    private static func makeSingleContent(
        commitment: Commitment, fireDate: Date
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Time for: \(commitment.title)"
        let slot = commitment.slots.first(where: {
            $0.occurrence(on: Time.startOfDay(for: fireDate))?.start == fireDate
        })
        content.body = commitment.encouragements.randomElement() ?? slot?.timeOfDayText ?? ""
        content.userInfo = [
            "commitmentId": commitment.id.uuidString,
            "slotId": slot?.id.uuidString ?? "",
        ]
        return content
    }

    private static func makeMultiContent(commitments: [Commitment]) -> UNMutableNotificationContent
    {
        let content = UNMutableNotificationContent()
        content.title = "\(commitments.count) commitments starting now"
        let titles = commitments.map(\.title)
        let primary = titles.prefix(3).joined(separator: " · ")
        content.body = titles.count > 3 ? "\(primary) · +\(titles.count - 3) more" : primary
        content.userInfo = ["commitmentIds": commitments.map(\.id.uuidString)]
        return content
    }
}
