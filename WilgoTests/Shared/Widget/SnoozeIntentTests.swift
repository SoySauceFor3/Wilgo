import Foundation
import Testing
@testable import Wilgo

/// Deterministic tests for `SnoozeIntent`'s parameter wiring.
/// The `perform()` body talks to the real App Group store and ActivityKit, so the
/// snooze-persists + Live-Activity-refreshes behavior is covered by on-device manual
/// verification (see the implementation plan), not here.
extension WidgetSuite {
struct SnoozeIntentTests {
    @Test("convenience init round-trips slotId into the LiveActivityIntent parameter")
    func init_roundTripsSlotId() {
        let id = UUID()
        let intent = SnoozeIntent(slotId: id)
        #expect(intent.slotId == id.uuidString)
    }

    @Test("default init has an empty slotId")
    func defaultInit_emptySlotId() {
        let intent = SnoozeIntent()
        #expect(intent.slotId == "")
    }
}
}
