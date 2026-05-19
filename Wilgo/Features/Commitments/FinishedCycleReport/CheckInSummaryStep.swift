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
                print("[FCR] CheckInSummaryStep appeared — commitments=\(commitments.count) preTokenReport=\(preTokenReport.count) request=[\(request.startPsychDay), \(request.endPsychDay)) time=\(Date())")
                if preTokenReport.isEmpty {
                    print("[FCR] CheckInSummaryStep: onEmptyReport fired on appear")
                    onEmptyReport()
                }
            }
            .onChange(of: commitments.count) { old, new in
                print("[FCR] @Query commitments changed: \(old) → \(new) preTokenReport=\(preTokenReport.count) time=\(Date())")
                if preTokenReport.isEmpty, new > 0 {
                    // commitments loaded but report still empty — log why
                    print("[FCR] @Query: commitments loaded but preTokenReport still empty for window [\(request.startPsychDay), \(request.endPsychDay))")
                }
            }
            .onChange(of: preTokenReport.isEmpty) { _, isEmpty in
                print("[FCR] preTokenReport.isEmpty → \(isEmpty) time=\(Date())")
                if isEmpty {
                    print("[FCR] CheckInSummaryStep: onEmptyReport fired on preTokenReport change")
                    onEmptyReport()
                }
            }
    }
}
