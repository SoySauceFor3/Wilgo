import Foundation
import Testing
@testable import Wilgo

/// Exercises `AppSettings.upcomingCommitmentCount`, which reads through `AppSettings.store`.
/// Each test runs against an isolated `AppSettings.store` (via `withStored`), so keys
/// never leak into `UserDefaults.standard` or race other suites on the parallel runner.
extension AppSettingsSuite {
@Suite
struct AppSettingsUpcomingCountTests {
    private let key = AppSettings.upcomingCommitmentCountKey

    private func withStored(_ value: Int?, _ body: () -> Void) {
        withIsolatedAppSettings(value.map { [key: $0] } ?? [:]) { _ in body() }
    }

    @Test("absent key → default 3")
    func absentDefaultsToThree() {
        withStored(nil) {
            #expect(AppSettings.upcomingCommitmentCount == 3)
        }
    }

    @Test("stored positive value is returned as-is")
    func storedValueReturned() {
        withStored(7) {
            #expect(AppSettings.upcomingCommitmentCount == 7)
        }
    }

    @Test("stored 0 is preserved (not clamped to 1) — 0 hides Upcoming")
    func zeroPreserved() {
        withStored(0) {
            #expect(AppSettings.upcomingCommitmentCount == 0)
        }
    }

    @Test("negative stored value clamps to 0")
    func negativeClampsToZero() {
        withStored(-5) {
            #expect(AppSettings.upcomingCommitmentCount == 0)
        }
    }
}
}
