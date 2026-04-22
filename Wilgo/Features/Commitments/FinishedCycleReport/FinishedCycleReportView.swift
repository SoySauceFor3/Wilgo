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

    /// Phase 2: PT compensation applied once and frozen at navigation time.
    /// Computed from the live preTokenReport when the user taps "Next", so any
    /// backfills done on Page 1 are already reflected before PT is applied.
    /// Must NOT be recomputed after navigation — PositivityTokenCompensator mutates
    /// token.status to .used, so re-running it would see zero active tokens.
    @State private var finalReport: [CommitmentReport] = []
    @State private var showTokenStep = false

    var body: some View {
        NavigationStack {
            CheckInSummaryPage(commitmentReports: preTokenReport)
                .navigationTitle("Check-In Summary")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Next") {
                            finalReport = AfterPositivityTokenReportBuilder.apply(
                                to: preTokenReport,
                                allTokens: tokens
                            )
                            showTokenStep = true
                        }
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
        .onAppear {
            print("[FCR] FinishedCycleReportView appeared — commitments=\(commitments.count) tokens=\(tokens.count) preTokenReport=\(preTokenReport.count) time=\(Date())")
            if preTokenReport.isEmpty { dismiss() }
        }
        .onChange(of: commitments.count) { old, new in
            print("[FCR] @Query commitments changed: \(old) → \(new) time=\(Date())")
        }
        .onChange(of: preTokenReport.isEmpty) { _, isEmpty in
            print("[FCR] preTokenReport.isEmpty → \(isEmpty) time=\(Date())")
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
