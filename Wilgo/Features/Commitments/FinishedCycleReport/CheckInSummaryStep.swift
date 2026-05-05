import SwiftData
import SwiftUI

struct CheckInSummaryStep: View {
    let request: FinishedCycleReportRequest
    let onNext: ([CommitmentReport]) -> Void
    let onEmptyReport: () -> Void

    @Query(sort: \Commitment.createdAt, order: .forward) private var commitments: [Commitment]

    private var preTokenReport: [CommitmentReport] {
        PreTokenReportBuilder.build(
            commitments: commitments,
            startPsychDay: request.startPsychDay,
            endPsychDay: request.endPsychDay
        )
    }

    var body: some View {
        CheckInSummaryPage(commitmentReports: preTokenReport)
            .navigationTitle("Check-In Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Next") {
                        onNext(preTokenReport)
                    }
                }
            }
            .onAppear {
                print("[FCR] CheckInSummaryStep appeared — commitments=\(commitments.count) preTokenReport=\(preTokenReport.count) time=\(Date())")
                if preTokenReport.isEmpty { onEmptyReport() }
            }
            .onChange(of: commitments.count) { old, new in
                print("[FCR] @Query commitments changed: \(old) → \(new) time=\(Date())")
            }
            .onChange(of: preTokenReport.isEmpty) { _, isEmpty in
                print("[FCR] preTokenReport.isEmpty → \(isEmpty) time=\(Date())")
                if isEmpty { onEmptyReport() }
            }
    }
}
