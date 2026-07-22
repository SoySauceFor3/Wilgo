import Foundation
import Testing
@testable import Wilgo

/// Exercises `AppSettings.includeActiveSlotsInCatchUp`, which reads `UserDefaults.standard`.
/// Serialized + each test restores the key so they don't pollute one another or the app.
extension AppSettingsSuite {
@Suite(.serialized)
struct AppSettingsCatchUpTests {
    private let key = AppSettings.includeActiveSlotsInCatchUpReminderKey

    private func withStored(_ value: Bool?, _ body: () -> Void) {
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

    @Test("absent key → defaults to false (exclude active slots)")
    func absentDefaultsToFalse() {
        withStored(nil) {
            #expect(AppSettings.includeActiveSlotsInCatchUp == false)
        }
    }

    @Test("stored true is returned")
    func storedTrue() {
        withStored(true) {
            #expect(AppSettings.includeActiveSlotsInCatchUp == true)
        }
    }

    @Test("stored false is returned")
    func storedFalse() {
        withStored(false) {
            #expect(AppSettings.includeActiveSlotsInCatchUp == false)
        }
    }
}
}
