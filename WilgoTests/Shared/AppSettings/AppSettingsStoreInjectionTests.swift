import Foundation
import Testing
@testable import Wilgo

/// Verifies `AppSettings` reads from an injectable `store` rather than a hard-wired
/// `UserDefaults.standard`. This is what lets each test use an isolated UserDefaults
/// instance so suites mutating the same keys no longer race across the parallel runner.
extension AppSettingsSuite {
    @Suite
    struct AppSettingsStoreInjectionTests {
        /// Runs `body` with `AppSettings.store` bound (task-locally) to a private, empty
        /// UserDefaults instance, cleaning it up afterward.
        private func withIsolatedStore(_ body: (UserDefaults) -> Void) {
            let suiteName = "test.\(UUID().uuidString)"
            let isolated = UserDefaults(suiteName: suiteName)!
            defer { isolated.removePersistentDomain(forName: suiteName) }
            AppSettings.$store.withValue(isolated) {
                body(isolated)
            }
        }

        @Test("reads reflect the injected store, not UserDefaults.standard")
        func readsFromInjectedStore() {
            withIsolatedStore { store in
                store.set(false, forKey: AppSettings.catchUpRemindersEnabledKey)
                #expect(AppSettings.catchUpRemindersEnabled == false)
                store.set(true, forKey: AppSettings.catchUpRemindersEnabledKey)
                #expect(AppSettings.catchUpRemindersEnabled == true)
            }
        }

        @Test("a value written in one isolated store is invisible to the next")
        func isolatedStoresDoNotLeak() {
            // Writing false in one isolated binding must not affect a fresh binding —
            // proving each test's store is independent (and that nothing leaks to the
            // process-wide default). No mutation of UserDefaults.standard here.
            let key = AppSettings.slotStartNotificationsEnabledKey
            withIsolatedStore { store in
                store.set(false, forKey: key)
                #expect(AppSettings.slotStartNotificationsEnabled == false)
            }
            // A brand-new isolated store has never seen the key → defaults to true.
            withIsolatedStore { _ in
                #expect(AppSettings.slotStartNotificationsEnabled == true)
            }
        }
    }
}
