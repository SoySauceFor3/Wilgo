import Foundation
import Testing
@testable import Wilgo

/// Conformer that records the order of template events. `nextWakeEarliestDate` is read
/// inside `scheduleBackgroundTask()`, so its getter marks the "schedule" step.
/// The real `BGWake.submit` runs with an unregistered identifier — it throws inside,
/// which BGWake logs and swallows; expected and harmless in the test host.
private enum RecordingScheduler: BackgroundRefreshScheduler {
    @MainActor static var events: [String] = []
    static let backgroundTaskIdentifier = "wilgo.test.recording"
    @MainActor static var nextWakeEarliestDate: Date {
        events.append("schedule")
        return Date().addingTimeInterval(60)
    }
    @MainActor static func performWork() async {
        events.append("work")
    }
}

extension LiveUpdatesSuite.InfrastructureSuite {
struct BackgroundRefreshSchedulerTests {
    @Test("refresh re-queues the next wake BEFORE running the work")
    @MainActor
    func refresh_schedulesBeforeWork() async {
        RecordingScheduler.events = []
        await RecordingScheduler.refresh()
        #expect(RecordingScheduler.events == ["schedule", "work"])
    }
}
}
