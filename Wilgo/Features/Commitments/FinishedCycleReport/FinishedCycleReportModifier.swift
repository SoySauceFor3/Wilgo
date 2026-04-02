import SwiftData
import SwiftUI

/// Manages the "should the sheet appear?" decision.
/// Owns the watermark check, the pending-report state, and the triggers
/// (initial task + scene-phase activation), so call sites only need
/// `.finishedCycleReport()`.
struct FinishedCycleReportModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingReport: FinishedCycleReportRequest?

    func body(content: Content) -> some View {
        content
            #if DEBUG
                .environment(\.triggerCycleReport, checkAndShow)
            #endif
            .fullScreenCover(item: $pendingReport) { request in
                FinishedCycleReportSheet(request: request)
            }
            .task(id: scenePhase) {  // the id parameter is a change detector + fires on app's first launch.
                if scenePhase == .active { checkAndShow() }
            }
    }

    private func checkAndShow() {
        // Only set/replace the sheet when there's an actual report to show.
        // If the user is currently looking at the sheet, we don't want to
        // automatically dismiss it due to a refresh tick (by then request might be None).
        if let request = reportRange() {
            pendingReport = request
        }
    }
}

/// Calculate the date range for the report (i.e. last report date - now)
///
/// Side effect:
/// reads persisted watermark, and advances it to now.
///
/// Notes:
/// - If persisted watermark is `0`, this is first app run: establish baseline
///   at current psych-day and do not show historical cycles.
private func reportRange() -> FinishedCycleReportRequest? {
    let previousRef = UserDefaults.standard.double(
        forKey: AppSettings.finishedCycleReportLastShownPsychDayKey
    )
    let nowPsychDay = Time.psychDay(for: Time.now())
    // Persist watermark updates regardless of whether we show anything.
    UserDefaults.standard.set(
        toPsychDayRef(nowPsychDay),
        forKey: AppSettings.finishedCycleReportLastShownPsychDayKey
    )
    // First bootstrap: establish baseline and do not show historical cycles.
    guard previousRef != 0 else { return nil }

    let startPsychDay = fromPsychDayRef(previousRef)
    // No completed cycle is possible if the window has zero width.
    guard startPsychDay < nowPsychDay else { return nil }

    return FinishedCycleReportRequest(
        startPsychDay: startPsychDay,
        endPsychDay: nowPsychDay
    )
}

private func toPsychDayRef(_ date: Date) -> Double {
    date.timeIntervalSinceReferenceDate
}

private func fromPsychDayRef(_ ref: Double) -> Date {
    Date(timeIntervalSinceReferenceDate: ref)
}
