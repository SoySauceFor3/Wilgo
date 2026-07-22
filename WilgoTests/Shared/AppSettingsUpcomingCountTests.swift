import Foundation
import Testing
@testable import Wilgo

/// Exercises `AppSettings.upcomingCommitmentCount`, which reads `UserDefaults.standard`.
/// Serialized + each test restores the key so they don't pollute one another or the app.
@Suite(.serialized)
struct AppSettingsUpcomingCountTests {
    private let key = AppSettings.upcomingCommitmentCountKey

    private func withStored(_ value: Int?, _ body: () -> Void) {
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
