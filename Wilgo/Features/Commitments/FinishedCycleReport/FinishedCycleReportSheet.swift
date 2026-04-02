import SwiftData
import SwiftUI

struct FinishedCycleReportSheet: View {
    let request: FinishedCycleReportRequest
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Commitment.createdAt, order: .forward) private var commitments: [Commitment]
    @Query(sort: \PositivityToken.createdAt, order: .forward) private var tokens: [PositivityToken]

    /// Recomputed whenever SwiftData notifies a change to commitments or tokens
    /// (e.g. after a backfill), keeping both pages in sync automatically.
    private var report: FinishedCycleReport {
        FinishedCycleReportBuilder.build(
            commitments: commitments,
            startPsychDay: request.startPsychDay,
            endPsychDay: request.endPsychDay,
            allTokens: tokens
        )
    }

    @State private var showTokenStep = false

    var body: some View {
        NavigationStack {
            CheckInSummaryPage(report: report)
                .navigationTitle("Check-In Summary")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Next") { showTokenStep = true }
                    }
                }
                .navigationDestination(isPresented: $showTokenStep) {
                    PositivityTokenPage(report: report)
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
