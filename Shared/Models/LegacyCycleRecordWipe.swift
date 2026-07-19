import Foundation
import SwiftData

/// One-time cleanup for legacy `CycleRecord` rows whose persisted `outcome` raw
/// value is `"letGo"` / `"other"` — cases that were removed from `CycleOutcome`
/// and no longer map to a valid case, which can crash SwiftData when it
/// materializes such a row on fetch. The FCR/CycleRecord feature is unreleased,
/// so we start cycle history fresh instead of migrating.
enum LegacyCycleRecordWipe {
    static let defaultsKey = "didWipeLegacyCycleRecords_v2"

    /// Deletes every `CycleRecord` row exactly once per install, guarded by a
    /// UserDefaults flag so future records are never touched. `defaults` is
    /// injectable for testability.
    ///
    /// Deleting `CycleRecord`s is safe for related models:
    /// - `consumedPT` uses `.nullify`, so each linked `PositivityToken` survives
    ///   and is freed back to the journal.
    /// - `commitment` cascade is `Commitment → CycleRecord`, not the reverse, so
    ///   commitments are untouched.
    ///
    /// NOTE: `delete(model:)` is a batch delete — it does NOT run delete rules or
    /// update *already-materialized* in-memory inverse relationships this session.
    /// That's fine only because this runs at app `init()`, before any view has
    /// fetched a `CycleRecord`/`PositivityToken`. Do not call it later in the
    /// lifecycle without re-checking that assumption.
    @MainActor
    static func runIfNeeded(context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: defaultsKey) else { return }
        do {
            try context.delete(model: CycleRecord.self)
            try context.save()
            defaults.set(true, forKey: defaultsKey)
        } catch {
            // If the wipe itself fails, do NOT set the flag so it retries next
            // launch. Log rather than crash the app on startup.
            print("LegacyCycleRecordWipe failed: \(error)")
        }
    }
}
