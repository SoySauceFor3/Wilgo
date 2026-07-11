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
                await CatchUpReminder.updateAndScheduleNotificationAndBackgroundTask()
            }
        }
        scheduler?.start()
    }

    // MARK: - Background task

    private static let backgroundTaskIdentifier = "wilgo.catchup-reminder-scheduler"
    static func registerBackgroundTask() {
        BGWake.register(backgroundTaskIdentifier) {
            await updateAndScheduleNotificationAndBackgroundTask()
        }
    }

    // MARK: - Main entry point

    /// Async so callers that must not outlive the work — the BGAppRefreshTask handler, which may
    /// only `setTaskCompleted` after the notification store is actually updated — can await it.
    /// App-alive callers may fire-and-forget with `Task { await ... }`.
    @MainActor
    static func updateAndScheduleNotificationAndBackgroundTask(
        now: Date? = nil
    ) async {
        let now = now ?? Time.now()
        let context = ModelContext.wilgoMain
        let commitments = (try? context.fetch(.activeOnly)) ?? []
        // Remind every behind commitment (not just the Stage's catch-up bucket): a behind commitment
        // sitting in Upcoming's top-N still needs catching up. `behindForReminder` reads the
        // characterization layer directly, so it isn't gated by the closest-N bucketing.
        let characteristics =
            commitments
            .filter { $0.isActiveForReminders(now: now) }
            .map { StageCharacterization.characteristics(of: $0, now: now) }
        let catchUp = StageCharacterization.behindForReminder(
            characteristics: characteristics,
            includeCurrent: AppSettings.includeActiveSlotsInCatchUp
        )

        updateCatchUpCommitmentsStorage(catchUp: catchUp, now: now)
        // Re-schedule before the notification work so a mid-flight kill still leaves a wake queued.
        scheduleBackgroundTask(now: now)
        await scheduleNotificationPost(for: catchUp, now: now)
    }

    // MARK: - Background task scheduling

    /// Queue the next catch-up reminder.
    static func scheduleBackgroundTask(
        now _: Date
    ) {
        BGWake.submit(backgroundTaskIdentifier, earliestBeginDate: Date().addingTimeInterval(1 * 60 * 60))
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
        catchUp: [CommitmentCharacteristics],
        now: Date = Time.now()
    ) {
        let defaults = UserDefaults.standard
        let currentIDs = Set(catchUp.map(\.commitment.id))

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
        for catchUp: [CommitmentCharacteristics]
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default

        guard !catchUp.isEmpty else {
            content.title = "Catch up on your commitments"
            content.body = "Open Wilgo to review your commitments."
            return content
        }

        let commitments = catchUp.map(\.commitment)
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

    @MainActor
    private static func scheduleNotificationPost(
        for catchUp: [CommitmentCharacteristics], now: Date
    ) async {
        let center = UNUserNotificationCenter.current()
        guard await (try? center.requestAuthorization(options: [.alert, .sound])) == true else {
            return
        }

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
            try? await center.add(request)
        }
    }
}
