import BackgroundTasks
import Foundation
import SwiftData
import UserNotifications

enum CatchUpReminder {
    // MARK: - Notification IDs

    private static let notificationIDPrefix = "wilgo.catchup."
    static let maxPendingCount = 10

    // All IDs we own — used for bulk cancel.
    private static var allNotificationIDs: [String] {
        (0..<maxPendingCount).map { "\(notificationIDPrefix)\($0)" }
    }

    // MARK: - Backoff offsets

    // Offsets in hours from lastNewCatchUpCommitmentDate.
    // internal so tests can verify the sequence without duplicating it.
    static let catchUpOffsetHours: [Double] = [
        1, 3, 7, 15,
        24,  // 1 day
        48,  // 2 days
        96,  // 4 days
        168,  // 1 week
        336,  // 2 weeks
        672,  // 4 weeks
    ]

    // MARK: - In-app scheduler

    // scheduler to make the "real work" run once a hour as long as the app is active.
    // if the app get's inactive/background, if during the hour-long gap, nothing changes.
    // if the app get's inactive/background when the timer fires, that time's handler exeuction will be missed.
    private static var scheduler: InAppScheduler?
    static func startHourlyRunWhileActive() {
        guard scheduler == nil else { return }  // avoid double-start
        scheduler = InAppScheduler(interval: 60 * 60) {
            Task { @MainActor in
                CatchUpReminder.updateAndScheduleNotificationAndBackgroundTask()
            }
        }
        scheduler?.start()
    }

    // MARK: - Background task

    private static let backgroundTaskIdentifier = "wilgo.catchup-reminder-scheduler"
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
                updateAndScheduleNotificationAndBackgroundTask()
                refreshTask.setTaskCompleted(success: true)
            }
        }
    }

    // MARK: - Main entry point

    @MainActor
    static func updateAndScheduleNotificationAndBackgroundTask(
        now: Date? = nil
    ) {
        let now = now ?? Time.now()
        let context = ModelContext(WilgoApp.sharedModelContainer)
        let commitments = (try? context.fetch(FetchDescriptor<Commitment>())) ?? []
        let remindersOn = commitments.filter(\.isRemindersEnabled)
        let catchUp = CommitmentAndSlot.catchUpWithBehind(commitments: remindersOn)

        updateCatchUpCommitmentsStorage(catchUp: catchUp, now: now)
        scheduleNotificationPost(for: catchUp, now: now)
        scheduleBackgroundTask(now: now)
    }

    // MARK: - Background task scheduling

    /// Queue the next catch-up reminder.
    static func scheduleBackgroundTask(
        now _: Date
    ) {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(1 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - UserDefaults storage

    private static let lastNewCatchUpCommitmentDateKey =
        "CatchUpReminderService.lastNewCatchUpCommitmentDate"
    private static let lastCatchUpCommitmentsKey: String =
        "CatchUpReminderService.lastCatchUpCommitments"

    // compares current catch-up IDs against what was stored last time.
    // If any are new, stamps lastNewCatchUpCommitmentDate = now. This is the anchor date for the chain
    // NOTE: because this function runs roughly 1/hour when the app is not active, so the date might be slightly outdated.
    private static func updateCatchUpCommitmentsStorage(
        catchUp: [CommitmentAndSlot.WithBehind],
        now: Date = Time.now()
    ) {
        let defaults = UserDefaults.standard
        let currentIDs = Set(catchUp.map(\.0.id))

        let prevRawIDs = defaults.stringArray(forKey: lastCatchUpCommitmentsKey) ?? []
        let prevIDs = Set(prevRawIDs.compactMap { UUID(uuidString: $0) })

        let newIDs = currentIDs.subtracting(prevIDs)
        if !newIDs.isEmpty {
            defaults.set(now, forKey: lastNewCatchUpCommitmentDateKey)
        }

        defaults.set(currentIDs.map(\.uuidString), forKey: lastCatchUpCommitmentsKey)
    }

    // MARK: - Fire date computation

    /// Returns up to `maxPendingCount` future fire dates anchored at `anchorDate`.
    /// Dates in the past (< now) are skipped; the chain starts from the first future offset.
    static func fireDates(from anchorDate: Date, now: Date) -> [Date] {
        catchUpOffsetHours
            .map { anchorDate.addingTimeInterval($0 * 3600) }
            .filter { $0 > now }
            .prefix(maxPendingCount)
            .map(\.self)
    }

    // MARK: - Notification content

    private static func makeNotificationContent(
        for catchUp: [CommitmentAndSlot.WithBehind]
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default

        guard !catchUp.isEmpty else {
            content.title = "Catch up on your commitments"
            content.body = "Open Wilgo to review your commitments."
            return content
        }

        let commitments = catchUp.map(\.0)
        let count = commitments.count

        if count == 1, let commitment = commitments.first {
            content.title = "Catch up: \(commitment.title)"
            content.body = "You have 1 commitment to catch up on. Open Wilgo to do it now."
            return content
        }

        content.title = "Catch up on \(count) commitments"
        let titles = commitments.map(\.title)
        let primary = titles.prefix(3).joined(separator: " · ")
        if titles.count > 3 {
            content.body = "\(primary) · +\(titles.count - 3) more"
        } else {
            content.body = primary
        }
        return content
    }

    // MARK: - Notification scheduling

    private static func scheduleNotificationPost(
        for catchUp: [CommitmentAndSlot.WithBehind], now: Date
    ) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            // Cancel the entire chain (including legacy single-ID).
            center.removePendingNotificationRequests(withIdentifiers: allNotificationIDs)

            guard !catchUp.isEmpty else { return }

            guard
                let anchorDate = UserDefaults.standard.object(
                    forKey: lastNewCatchUpCommitmentDateKey) as? Date
            else { return }

            let dates = fireDates(from: anchorDate, now: now)
            let content = makeNotificationContent(for: catchUp)

            for (index, fireDate) in dates.enumerated() {
                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: fireDate
                )
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "\(notificationIDPrefix)\(index)",
                    content: content,
                    trigger: trigger
                )
                center.add(request)
            }
        }
    }
}
