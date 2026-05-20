import Foundation
import Testing
import UserNotifications
@testable import Wilgo

struct CycleEndNotificationSchedulerTests {
    // MARK: - trigger(for:)

    @Test func trigger_daily_repeatsEveryDay() {
        let trigger = CycleEndNotificationScheduler.trigger(for: .daily)
        #expect(trigger.repeats == true)
        #expect(trigger.dateComponents.hour == 0)
        #expect(trigger.dateComponents.minute == 0)
        #expect(trigger.dateComponents.weekday == nil)
        #expect(trigger.dateComponents.day == nil)
    }

    @Test func trigger_weekly_firesMondayMidnight() {
        UserDefaults.standard.set(true, forKey: AppSettings.weekStartsOnMondayKey)
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey) }

        let trigger = CycleEndNotificationScheduler.trigger(for: .weekly)
        #expect(trigger.repeats == true)
        #expect(trigger.dateComponents.hour == 0)
        #expect(trigger.dateComponents.weekday == 2) // 2 = Monday
        #expect(trigger.dateComponents.day == nil)
    }

    @Test func trigger_monthly_firesFirstOfMonth() {
        let trigger = CycleEndNotificationScheduler.trigger(for: .monthly)
        #expect(trigger.repeats == true)
        #expect(trigger.dateComponents.hour == 0)
        #expect(trigger.dateComponents.day == 1)
        #expect(trigger.dateComponents.weekday == nil)
    }
}
