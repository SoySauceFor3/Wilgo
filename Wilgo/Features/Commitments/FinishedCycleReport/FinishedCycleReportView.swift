import SwiftData
import SwiftUI

struct FinishedCycleReportView: View {
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

    /// Phase 2: PT compensation applied once and frozen in @State.
    /// Must NOT be a computed property — PositivityTokenCompensator mutates token.status
    /// to .used, so recomputing after that mutation would see zero active tokens and
    /// return an empty result (showing "0 PT used").
    @State private var finalReport: [CommitmentReport] = []
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
            let report = PreTokenReportBuilder.build(
                commitments: commitments,
                startPsychDay: request.startPsychDay,
                endPsychDay: request.endPsychDay
            )
            if report.isEmpty {
                dismiss()
                return
            }
            finalReport = AfterPositivityTokenReportBuilder.apply(
                to: report,
                allTokens: tokens
            )
        }
        .onChange(of: preTokenReport.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
    }
}

// MARK: - Preview helpers

struct FinishedCycleReportViewPreview: View {
    var body: some View {
        let endPsychDay = Calendar.current.startOfDay(for: Date())
        let startPsychDay =
            Calendar.current.date(byAdding: .day, value: -21, to: endPsychDay) ?? endPsychDay
        let request = FinishedCycleReportRequest(
            startPsychDay: startPsychDay,
            endPsychDay: endPsychDay
        )
        FinishedCycleReportView(request: request)
    }
}

#Preview {
    let container = HeatmapPreviewFactory.richHistoryContainer()
    FinishedCycleReportViewPreview()
        .modelContainer(container)
        .environmentObject(CheckInUndoManager())
}
