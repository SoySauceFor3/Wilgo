import SwiftData
import SwiftUI

/// Manages the "should the sheet appear?" decision.
/// Owns the watermark check, the pending-report state, and the triggers
/// (initial task + scene-phase activation), so call sites only need
/// `.finishedCycleReport()`.
struct FinishedCycleReportModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @State private var reportRequest: FinishedCycleReportRequest?

    func body(content: Content) -> some View {
        content
            #if DEBUG
                .environment(\.triggerCycleReport, checkAndShow)
            #endif
            .fullScreenCover(item: $reportRequest) { request in
                FinishedCycleReportView(request: request)
            }
            .task(id: scenePhase) {  // the id parameter is a change detector + fires on app's first launch.
                if scenePhase == .active { checkAndShow() }
            }
    }

    private func checkAndShow() {
        guard let request = peekReportRange() else { return }
        guard hasFinishedCycles(in: request) else { return }
        advanceWatermark()
        reportRequest = request
    }

    private func hasFinishedCycles(in request: FinishedCycleReportRequest) -> Bool {
        // This fetch is intentionally synchronous on the main actor.
        // The data set is small (O(tens) of commitments) and this is a one-time
        // check on scene activation — not worth the complexity of actor hopping.
        // If commitment data ever grows large, move to a background ModelContext.
        let commitments = (try? modelContext.fetch(FetchDescriptor<Commitment>())) ?? []
        return commitments.contains { commitment in
            let cycleEnd = commitment.cycle.endDayOfCycle(including: request.startPsychDay)
            return cycleEnd <= request.endPsychDay
        }
    }
}

/// Calculate the date range for the report (i.e. last report date - now).
///
/// Pure — no side effects. Reads the persisted watermark and returns the
/// window if valid, but does NOT write anything to UserDefaults.
///
/// Notes:
/// - If persisted watermark is `0`, this is first app run: establish baseline
///   at current psych-day and do not show historical cycles.
private func peekReportRange() -> FinishedCycleReportRequest? {
    let previousRef = UserDefaults.standard.double(
        forKey: AppSettings.finishedCycleReportLastShownPsychDayKey
    )
    let nowPsychDay = Time.startOfDay(for: Time.now())
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

private func advanceWatermark() {
    let nowPsychDay = Time.startOfDay(for: Time.now())
    UserDefaults.standard.set(
        toPsychDayRef(nowPsychDay),
        forKey: AppSettings.finishedCycleReportLastShownPsychDayKey
    )
}

private func toPsychDayRef(_ date: Date) -> Double {
    date.timeIntervalSinceReferenceDate
}

private func fromPsychDayRef(_ ref: Double) -> Date {
    Date(timeIntervalSinceReferenceDate: ref)
}
