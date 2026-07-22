import Foundation
import Testing
import UserNotifications
@testable import Wilgo

extension LiveUpdatesSuite.SchedulersSuite {
@Suite(.serialized)
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

    // MARK: - AppSettings gate

    /// `refresh()` gates all scheduling on `AppSettings.cycleEndNotificationsEnabled` before it
    /// ever touches `UNUserNotificationCenter`, so it cannot be exercised end-to-end without
    /// mocking the system notification center (disallowed). The testable seam is the gate
    /// condition itself: confirms the toggle the scheduler reads defaults to enabled and
    /// correctly reports disabled when the user has opted out, which is what `refresh()` branches on.
    private func withStored(_ key: String, _ value: Bool?, _ body: () -> Void) {
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        body()
    }

    @Test("refresh's gate: cycleEndNotificationsEnabled defaults to true (no opt-out)")
    func gate_defaultsToEnabled() {
        withStored(AppSettings.cycleEndNotificationsEnabledKey, nil) {
            #expect(AppSettings.cycleEndNotificationsEnabled == true)
        }
    }

    @Test("refresh's gate: cycleEndNotificationsEnabled false when user disables the toggle")
    func gate_disabledWhenToggledOff() {
        withStored(AppSettings.cycleEndNotificationsEnabledKey, false) {
            #expect(AppSettings.cycleEndNotificationsEnabled == false)
        }
    }
}
}
