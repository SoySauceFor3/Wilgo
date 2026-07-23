import Foundation
import Testing
@testable import Wilgo

/// Exercises `AppSettings.includeActiveSlotsInCatchUp`, which reads through `AppSettings.store`.
/// Each test runs against an isolated `AppSettings.store` (via `withStored`), so keys
/// never leak into `UserDefaults.standard` or race other suites on the parallel runner.
extension AppSettingsSuite {
@Suite
struct AppSettingsCatchUpTests {
    private let key = AppSettings.includeActiveSlotsInCatchUpReminderKey

    private func withStored(_ value: Bool?, _ body: () -> Void) {
        withIsolatedAppSettings(value.map { [key: $0] } ?? [:]) { _ in body() }
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
