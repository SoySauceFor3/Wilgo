import SwiftData
import SwiftUI

struct FinishedCycleReportSheet: View {
    let request: FinishedCycleReportRequest
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Commitment.createdAt, order: .forward) private var commitments: [Commitment]
    @Query(sort: \PositivityToken.createdAt, order: .forward) private var tokens: [PositivityToken]

    /// Phase 1: raw check-in data only, no PT compensation.
    /// Recomputed on any SwiftData change to commitments (e.g. after a backfill).
    private var preTokenReport: [CommitmentReport] {
        PreTokenReportBuilder.build(
            commitments: commitments,
            startPsychDay: request.startPsychDay,
            endPsychDay: request.endPsychDay
        )
    }

    /// Phase 2: PT compensation applied on top of `preTokenReport`.
    /// Recomputed whenever either commitments or tokens change.
    private var finalReport: [CommitmentReport] {
        AfterPositivityTokenReportBuilder.apply(
            to: preTokenReport,
            allTokens: tokens
        )
    }

    @State private var showTokenStep = false

    var body: some View {
        NavigationStack {
            CheckInSummaryPage(commitmentReports: preTokenReport)
                .navigationTitle("Check-In Summary")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Next") { showTokenStep = true }
                    }
                }
                .navigationDestination(isPresented: $showTokenStep) {
                    PositivityTokenPage(commitmentReports: finalReport)
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
            if preTokenReport.isEmpty { dismiss() }
        }
        .onChange(of: preTokenReport.isEmpty) { _, isEmpty in
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
