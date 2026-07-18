import Foundation
import Testing
@testable import Wilgo

/// Exercises the four category-enabled flags on `AppSettings`, all of which read `UserDefaults.standard`
/// and default to `true` when absent. Serialized + each test restores the key so they don't pollute
/// one another or the app.
@Suite(.serialized)
struct AppSettingsCategoryTogglesTests {
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

    // MARK: - slotStartNotificationsEnabled

    @Test("slot start: absent key → defaults to true")
    func slotStartAbsentDefaultsToTrue() {
        withStored(AppSettings.slotStartNotificationsEnabledKey, nil) {
            #expect(AppSettings.slotStartNotificationsEnabled == true)
        }
    }

    @Test("slot start: stored true is returned")
    func slotStartStoredTrue() {
        withStored(AppSettings.slotStartNotificationsEnabledKey, true) {
            #expect(AppSettings.slotStartNotificationsEnabled == true)
        }
    }

    @Test("slot start: stored false is returned")
    func slotStartStoredFalse() {
        withStored(AppSettings.slotStartNotificationsEnabledKey, false) {
            #expect(AppSettings.slotStartNotificationsEnabled == false)
        }
    }

    // MARK: - catchUpRemindersEnabled

    @Test("catch-up reminders: absent key → defaults to true")
    func catchUpRemindersAbsentDefaultsToTrue() {
        withStored(AppSettings.catchUpRemindersEnabledKey, nil) {
            #expect(AppSettings.catchUpRemindersEnabled == true)
        }
    }

    @Test("catch-up reminders: stored true is returned")
    func catchUpRemindersStoredTrue() {
        withStored(AppSettings.catchUpRemindersEnabledKey, true) {
            #expect(AppSettings.catchUpRemindersEnabled == true)
        }
    }

    @Test("catch-up reminders: stored false is returned")
    func catchUpRemindersStoredFalse() {
        withStored(AppSettings.catchUpRemindersEnabledKey, false) {
            #expect(AppSettings.catchUpRemindersEnabled == false)
        }
    }

    // MARK: - cycleEndNotificationsEnabled

    @Test("cycle end: absent key → defaults to true")
    func cycleEndAbsentDefaultsToTrue() {
        withStored(AppSettings.cycleEndNotificationsEnabledKey, nil) {
            #expect(AppSettings.cycleEndNotificationsEnabled == true)
        }
    }

    @Test("cycle end: stored true is returned")
    func cycleEndStoredTrue() {
        withStored(AppSettings.cycleEndNotificationsEnabledKey, true) {
            #expect(AppSettings.cycleEndNotificationsEnabled == true)
        }
    }

    @Test("cycle end: stored false is returned")
    func cycleEndStoredFalse() {
        withStored(AppSettings.cycleEndNotificationsEnabledKey, false) {
            #expect(AppSettings.cycleEndNotificationsEnabled == false)
        }
    }

    // MARK: - nowLiveActivityEnabled

    @Test("now live activity: absent key → defaults to true")
    func nowLiveActivityAbsentDefaultsToTrue() {
        withStored(AppSettings.nowLiveActivityEnabledKey, nil) {
            #expect(AppSettings.nowLiveActivityEnabled == true)
        }
    }

    @Test("now live activity: stored true is returned")
    func nowLiveActivityStoredTrue() {
        withStored(AppSettings.nowLiveActivityEnabledKey, true) {
            #expect(AppSettings.nowLiveActivityEnabled == true)
        }
    }

    @Test("now live activity: stored false is returned")
    func nowLiveActivityStoredFalse() {
        withStored(AppSettings.nowLiveActivityEnabledKey, false) {
            #expect(AppSettings.nowLiveActivityEnabled == false)
        }
    }
}
