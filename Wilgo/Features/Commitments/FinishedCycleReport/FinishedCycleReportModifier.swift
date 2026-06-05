import SwiftData
import SwiftUI

/// Manages the "should the sheet appear?" decision.
/// Owns the watermark check, the pending-report state, and the triggers
/// (initial task + scene-phase activation), so call sites only need
/// `.finishedCycleReport()`.
struct FinishedCycleReportModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @State private var presentationState = FinishedCycleReportPresentationState()

    func body(content: Content) -> some View {
        content
            #if DEBUG
                .environment(\.triggerCycleReport, checkAndShow)
            #endif
            .fullScreenCover(isPresented: $presentationState.shouldShowReport) {
                if let request = presentationState.reportRequest {
                    FinishedCycleReportView(
                        request: request,
                        onFinished: {
                            print("[FCR] onFinished called (user completed report) time=\(Date())")
                            finalizeReport(request)
                        }
                    )
                } else {
                    // reportRequest was nil when cover opened — should never happen
                    let _ = print("[FCR] fullScreenCover body: reportRequest is nil!")
                    Color.clear
                }
            }
            .onChange(of: presentationState.shouldShowReport) { _, newValue in
                print("[FCR] shouldShowReport → \(newValue) time=\(Date())")
            }
            .task(id: scenePhase) {  // the id parameter is a change detector + fires on app's first launch.
                print("[FCR] scenePhase changed → \(scenePhase) time=\(Date())")
                if scenePhase == .active {
                    checkAndShow()
                }
            }
    }

    private func checkAndShow() {
        guard let request = peekReportRange() else { return }
        presentationState.prepare(request)
        print(
            "[FCR] checkAndShow: fetch start — thread=\(Thread.isMainThread ? "main" : "bg") time=\(Date())"
        )
        let hasFinishedCycles: Bool
        do {
            hasFinishedCycles = try anyFinishedCycles(in: request)
        } catch {
            print(
                "[FCR] checkAndShow: fetch THREW \(error) — aborting without advancing watermark, will retry on next activation"
            )
            return
        }
        print(
            "[FCR] checkAndShow: fetch end — hasFinishedCycles=\(hasFinishedCycles) time=\(Date())")
        if hasFinishedCycles {
            presentationState.show()
        } else {
            print(
                "[FCR] checkAndShow: no finished cycles found — silently advancing watermark from \(request.startPsychDay) to \(request.endPsychDay)"
            )
            finalizeReport(request)
        }
    }

    private func finalizeReport(_ request: FinishedCycleReportRequest) {
        presentationState.finalize(request) { psychDay in
            advanceWatermark(to: psychDay)
        }

        do {
            let commitments = try modelContext.fetch(FetchDescriptor<Commitment>())
            normalizeExpiredTargetModes(in: commitments, afterReportedThrough: request.endPsychDay)
            try modelContext.save()
        } catch {
            print("[FCR] target mode normalization failed after report finalization: \(error)")
        }
    }

    private func anyFinishedCycles(in request: FinishedCycleReportRequest) throws -> Bool {
        // This fetch is intentionally synchronous on the main actor.
        // The data set is small (O(tens) of commitments) and this is a one-time
        // check on scene activation — not worth the complexity of actor hopping.
        // If commitment data ever grows large, move to a background ModelContext.
        let commitments = try modelContext.fetch(FetchDescriptor<Commitment>())
        print(
            "[FCR] anyFinishedCycles: fetched \(commitments.count) commitments, window=[\(request.startPsychDay), \(request.endPsychDay))"
        )
        for commitment in commitments {
            let cycleEnd = commitment.cycle.endDayOfCycle(including: request.startPsychDay)
            let matches = cycleEnd > request.startPsychDay && cycleEnd <= request.endPsychDay
            print(
                "[FCR]   commitment=\(commitment.title) cycleKind=\(commitment.cycle.kind) cycleEnd=\(cycleEnd) matches=\(matches)"
            )
        }
        return commitments.contains { commitment in
            let cycleEnd = commitment.cycle.endDayOfCycle(including: request.startPsychDay)
            // The cycle must end strictly after the window start (not already reported)
            // and at or before the window end.
            return cycleEnd > request.startPsychDay && cycleEnd <= request.endPsychDay
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
    print(
        "[FCR] peekReportRange: storedRef=\(previousRef) storedDate=\(Date(timeIntervalSinceReferenceDate: previousRef)) nowPsychDay=\(nowPsychDay)"
    )
    // First bootstrap: establish baseline so the report fires from tomorrow onward.
    // Do NOT show historical cycles — only cycles completed after this point are reported.
    guard previousRef != 0 else {
        print("[FCR] peekReportRange: first-launch bootstrap — writing today as watermark")
        advanceWatermark(to: nowPsychDay)
        return nil
    }

    let startPsychDay = fromPsychDayRef(previousRef)
    // No completed cycle is possible if the window has zero width.
    guard startPsychDay < nowPsychDay else { return nil }

    return FinishedCycleReportRequest(
        startPsychDay: startPsychDay,
        endPsychDay: nowPsychDay
    )
}

private func advanceWatermark(to psychDay: Date) {
    UserDefaults.standard.set(
        toPsychDayRef(psychDay),
        forKey: AppSettings.finishedCycleReportLastShownPsychDayKey
    )
}

func normalizeExpiredTargetModes(
    in _: [Commitment],
    afterReportedThrough _: Date
) {
    // no-op: InsOnly removed, target modes no longer auto-expire
}

private func toPsychDayRef(_ date: Date) -> Double {
    date.timeIntervalSinceReferenceDate
}

private func fromPsychDayRef(_ ref: Double) -> Date {
    Date(timeIntervalSinceReferenceDate: ref)
}

struct FinishedCycleReportPresentationState {
    var reportRequest: FinishedCycleReportRequest?
    var shouldShowReport = false

    mutating func prepare(_ request: FinishedCycleReportRequest) {
        reportRequest = request
        shouldShowReport = false
    }

    mutating func show() {
        shouldShowReport = true
    }

    mutating func finalize(
        _ request: FinishedCycleReportRequest,
        advanceWatermark: (Date) -> Void
    ) {
        advanceWatermark(request.endPsychDay)
        reportRequest = nil
        shouldShowReport = false
    }
}
