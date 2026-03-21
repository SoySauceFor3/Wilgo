import BackgroundTasks
import Foundation
import SwiftData
import UserNotifications

enum CatchUpReminder {
    // scheduler to make the "real work" run once a hour as long as the app is active.
    // if the app get's inactive/background, if during the hour-long gap, nothing changes.
    // if the app get's inactive/background when the timer fires, that time's handler exeuction will be missed.
    private static var scheduler: InAppScheduler?
    static func startHourlyRunWhileActive() {
        guard scheduler == nil else { return }  // avoid double-start
        scheduler = InAppScheduler(interval: 60 * 60) {
            Task.detached(priority: .utility) {
                CatchUpReminder.updateAndScheduleNotificationAndBackgroundTask()
            }
        }
        scheduler?.start()
    }

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
            updateAndScheduleNotificationAndBackgroundTask()
            refreshTask.setTaskCompleted(success: true)
        }
    }

    // The real work that we should do once in a while (hour)
    static func updateAndScheduleNotificationAndBackgroundTask(
        now: Date = Time.now()
    ) {
        let context = ModelContext(WilgoApp.sharedModelContainer)
        let commitments = (try? context.fetch(FetchDescriptor<Commitment>())) ?? []
        let catchUp = CommitmentAndSlot.catchUpWithBehind(commitments: commitments)

        updateCatchUpCommitmentsStorage(catchUp: catchUp, now: now)
        scheduleNotificationPost(for: catchUp, now: now)
        scheduleBackgroundTask(now: now)
    }

    /// Queue the next catch-up reminder.
    static func scheduleBackgroundTask(
        now: Date = Time.now()
    ) {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)

        request.earliestBeginDate = Date().addingTimeInterval(1 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static let lastNewCatchUpCommitmentDateKey =
        "CatchUpReminderService.lastNewCatchUpCommitmentDate"
    private static let lastCatchUpCommitmentsKey: String =
        "CatchUpReminderService.lastCatchUpCommitments"

    // NOTE: because this function runs roughly 1/hour when the app is not active, so the date might be slightly outdated.
    private static func updateCatchUpCommitmentsStorage(
        catchUp: [CommitmentAndSlot.WithBehind],
        now: Date = Time.now()
    ) {
        // 1. Get the currently stored catch-up commitments from UserDefaults.
        let defaults = UserDefaults.standard
        let currentIDs = Set(catchUp.map { $0.0.persistentModelID })

        let prevIDs: Set<PersistentIdentifier>
        if let prevData = defaults.data(forKey: lastCatchUpCommitmentsKey),
            let prevRawIDs = try? JSONDecoder().decode([String].self, from: prevData)
        {
            prevIDs = Set(prevRawIDs.compactMap { PersistentIdentifier.decode(from: $0) })
        } else {
            prevIDs = []
        }

        // 2. Compute new catch-up commitments not previously present.
        let newIDs = currentIDs.subtracting(prevIDs)

        // 3. If there are any new catch-up commitments (at least one ID not in prevIDs), update addition date.
        if !newIDs.isEmpty {
            defaults.set(now, forKey: lastNewCatchUpCommitmentDateKey)
        }

        // 4. Update the stored catch-up commitments.
        let idStrings = currentIDs.map { $0.encoded() }
        if let encoded = try? JSONEncoder().encode(Array(idStrings)) {
            defaults.set(encoded, forKey: lastCatchUpCommitmentsKey)
        }

    }

    private static func nextNotificationDate(
        lastNewCatchUpCommitmentDate: Date,
        now: Date = Time.now()
    ) -> Date {
        let defaults = UserDefaults.standard
        guard
            let lastNewCatchUpCommitmentDate = defaults.object(
                forKey: lastNewCatchUpCommitmentDateKey) as? Date
        else {
            return now  // If there is no last new catch-up commitment date, return the current time.
        }

        // Calculate the smallest power of 2 (n) such that fireDate = lastNewCatchUpCommitmentDate + (2^n - 1) * 1 hour is >= now
        // We start from the moment of noticing the new catch-up commitment, which can possibly be a little bit late.
        var n = 0
        var nextNotificationDate: Date
        repeat {
            let intervalHours = pow(2.0, Double(n)) - 1.0
            nextNotificationDate = lastNewCatchUpCommitmentDate.addingTimeInterval(
                intervalHours * 3600)
            n += 1
        } while nextNotificationDate < now
        return nextNotificationDate
    }

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

        let commitments = catchUp.map { $0.0 }
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
            let remaining = titles.count - 3
            content.body = "\(primary) · +\(remaining) more"
        } else {
            content.body = primary
        }

        return content
    }

    private static let notificationID: String = "wilgo.catchup"
    private static func scheduleNotificationPost(
        for catchUp: [CommitmentAndSlot.WithBehind], now: Date
    ) {
        let center: UNUserNotificationCenter = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            guard !catchUp.isEmpty else { return }  // if catchUp is empty, don't post a notification
            center.removePendingNotificationRequests(withIdentifiers: [notificationID])

            let content = makeNotificationContent(for: catchUp)
            let nextNotificationDate = nextNotificationDate(lastNewCatchUpCommitmentDate: now)
            let calendar = Calendar.current
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: nextNotificationDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: notificationID,
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }
}
