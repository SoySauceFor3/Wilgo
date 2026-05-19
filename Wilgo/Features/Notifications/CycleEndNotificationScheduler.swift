import Foundation
import SwiftData
import UserNotifications

enum CycleEndNotificationScheduler {
    private static let notificationIDPrefix = "wilgo.cycle-end."

    private static var allNotificationIDs: [String] {
        CycleKind.allCases.map { "\(notificationIDPrefix)\($0.rawValue.lowercased())" }
    }

    // MARK: - Main entry point

    @MainActor
    static func refresh() {
        let context = ModelContext(WilgoApp.sharedModelContainer)
        let commitments = (try? context.fetch(FetchDescriptor<Commitment>())) ?? []
        let activeKinds = Set(commitments.map(\.cycle.kind))
        scheduleNotifications(for: activeKinds)
    }

    // MARK: - Trigger computation

    /// Returns a repeating UNCalendarNotificationTrigger that fires at midnight
    /// at the end of each period for the given cycle kind.
    ///
    /// - Daily:   fires every day at 00:00 (weekday/day unset → repeats daily)
    /// - Weekly:  fires every Monday at 00:00
    /// - Monthly: fires on the 1st of every month at 00:00 (= end of previous month's cycle)
    static func trigger(for kind: CycleKind) -> UNCalendarNotificationTrigger {
        var components = DateComponents()
        components.hour = 0
        components.minute = 0
        components.second = 0
        switch kind {
        case .daily:
            break // no day component → repeats every day
        case .weekly:
            components.weekday = 2 // Monday
        case .monthly:
            components.day = 1 // 1st of month = exclusive end of previous month's cycle
        }
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
    }

    // MARK: - Notification content

    private static func makeContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Your cycle just ended"
        content.body = "Tap to see how it went."
        content.sound = .default
        return content
    }

    // MARK: - Scheduling

    private static func scheduleNotifications(for activeKinds: Set<CycleKind>) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            // Cancel all owned notifications, then re-schedule only active kinds.
            center.removePendingNotificationRequests(withIdentifiers: allNotificationIDs)

            let content = makeContent()
            for kind in activeKinds {
                let request = UNNotificationRequest(
                    identifier: "\(notificationIDPrefix)\(kind.rawValue.lowercased())",
                    content: content,
                    trigger: trigger(for: kind)
                )
                center.add(request)
            }
        }
    }
}
