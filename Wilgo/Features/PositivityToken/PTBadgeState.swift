import Foundation
import Observation

/// Owns the PT tab badge logic.
///
/// Injected into the environment at app root. Both MainTabView (reads hasNewCapacity
/// for the badge) and ListPositivityTokenView (calls markAsSeen) access it via
/// @Environment(PTBadgeState.self) without any bindings or prop threading.
///
/// capacitySeenByUser is persisted to UserDefaults so the badge survives restarts.
@Observable
final class PTBadgeState {
    private let defaults: UserDefaults
    private let key = "PTBadge.capacitySeenByUser"

    private(set) var capacitySeenByUser: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.capacitySeenByUser = defaults.integer(forKey: "PTBadge.capacitySeenByUser")
    }

    /// True when the store has more capacity than the user last saw.
    /// PTBadgeObserver keeps currentCapacity up to date.
    private(set) var currentCapacity: Int = 0

    var hasNewCapacity: Bool {
        currentCapacity > capacitySeenByUser
    }

    /// Called by PTBadgeObserver whenever @Query-driven capacity changes.
    func update(currentCapacity: Int) {
        self.currentCapacity = currentCapacity
    }

    /// Called by ListPositivityTokenView on appear and while visible on capacity change.
    func markAsSeen() {
        capacitySeenByUser = currentCapacity
        defaults.set(currentCapacity, forKey: key)
    }
}
