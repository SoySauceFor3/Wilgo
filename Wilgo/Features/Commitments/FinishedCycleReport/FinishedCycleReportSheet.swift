import SwiftData
import SwiftUI

struct FinishedCycleReportSheet: View {
    let request: FinishedCycleReportRequest
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Commitment.createdAt, order: .forward) private var commitments: [Commitment]
    @Query(sort: \PositivityToken.createdAt, order: .forward) private var tokens: [PositivityToken]

    /// Phase 1: raw check-in data only, no PT compensation.
    /// Recomputed on any SwiftData change to commitments (e.g. after a backfill).
    private var preTokenReport: FinishedCycleReport {
        FinishedCycleReportBuilder.buildPreToken(
            commitments: commitments,
            startPsychDay: request.startPsychDay,
            endPsychDay: request.endPsychDay
        )
    }

    /// Phase 2: PT compensation applied on top of `preTokenReport`.
    /// Recomputed whenever either commitments or tokens change.
    private var finalReport: FinishedCycleReport {
        FinishedCycleReportBuilder.applyPositivityTokens(
            to: preTokenReport,
            allTokens: tokens
        )
    }

    @State private var showTokenStep = false

    var body: some View {
        NavigationStack {
            CheckInSummaryPage(report: preTokenReport)
                .navigationTitle("Check-In Summary")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Next") { showTokenStep = true }
                    }
                }
                .navigationDestination(isPresented: $showTokenStep) {
                    PositivityTokenPage(report: finalReport)
                        .navigationTitle("Positivity Tokens")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { dismiss() }
                            }
                        }
                }
        }
        .task {
            if preTokenReport.commitments.isEmpty { dismiss() }
        }
        .onChange(of: preTokenReport.commitments.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
    }
}

// MARK: - Presenter modifier

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
        if let request = FinishedCycleReportBuilder.reportRange() {
            pendingReport = request
        }
    }
}

// MARK: - Preview helpers

struct FinishedCycleReportSheetPreview: View {
    var body: some View {
        let endPsychDay = Calendar.current.startOfDay(for: Date())
        let startPsychDay =
            Calendar.current.date(byAdding: .day, value: -21, to: endPsychDay) ?? endPsychDay
        let request = FinishedCycleReportRequest(
            startPsychDay: startPsychDay,
            endPsychDay: endPsychDay
        )
        FinishedCycleReportSheet(request: request)
    }
}

#Preview {
    let container = HeatmapPreviewFactory.richHistoryContainer()
    FinishedCycleReportSheetPreview()
        .modelContainer(container)
        .environmentObject(CheckInUndoManager())
}
