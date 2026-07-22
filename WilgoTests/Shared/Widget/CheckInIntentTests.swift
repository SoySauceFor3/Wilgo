import Foundation
import Testing
@testable import Wilgo

/// Deterministic tests for `CheckInIntent`'s parameter wiring.
/// The `perform()` body talks to the real App Group store and ActivityKit, so the
/// check-in-persists + Live-Activity-advances behavior is covered by on-device manual
/// verification (see the implementation plan), not here.
struct CheckInIntentTests {
    @Test("convenience init round-trips commitmentId and source into the LiveActivityIntent parameters")
    func init_roundTripsParameters() {
        let id = UUID()
        let intent = CheckInIntent(commitmentId: id, source: .liveActivity)
        #expect(intent.commitmentId == id.uuidString)
        #expect(intent.sourceRaw == CheckInSource.liveActivity.rawValue)
    }

    @Test("default init uses the widget source")
    func defaultInit_usesWidgetSource() {
        let intent = CheckInIntent()
        #expect(intent.commitmentId == "")
        #expect(intent.sourceRaw == CheckInSource.widget.rawValue)
    }
}
