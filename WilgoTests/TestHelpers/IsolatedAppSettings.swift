import Foundation
@testable import Wilgo

/// Runs `body` with `AppSettings.store` bound (task-locally) to a private, empty
/// UserDefaults instance. Any settings keys the body writes land in this isolated
/// store, never `UserDefaults.standard` — so suites touching the same keys don't
/// race one another across the parallel test runner.
///
/// Optional `values` seeds the store before `body` runs (use the `AppSettings.*Key`
/// constants as keys). The store is destroyed afterward.
func withIsolatedAppSettings(
    _ values: [String: Any] = [:],
    _ body: (UserDefaults) throws -> Void
) rethrows {
    let suiteName = "test.appsettings.\(UUID().uuidString)"
    let store = UserDefaults(suiteName: suiteName)!
    defer { store.removePersistentDomain(forName: suiteName) }
    for (key, value) in values {
        store.set(value, forKey: key)
    }
    try AppSettings.$store.withValue(store) {
        try body(store)
    }
}
