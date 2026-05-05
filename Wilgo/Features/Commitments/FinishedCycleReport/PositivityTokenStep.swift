import SwiftData
import SwiftUI

struct PositivityTokenStep: View {
    let preTokenReport: [CommitmentReport]
    let onDone: () -> Void

    @Query(sort: \PositivityToken.createdAt, order: .forward) private var tokens: [PositivityToken]
    @State private var preparedReport: PositivityTokenStepPreparedReport?

    var body: some View {
        Group {
            if let preparedReport {
                PositivityTokenPage(
                    commitmentReports: preparedReport.finalReport,
                    usageSummary: preparedReport.usageSummary
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Positivity Tokens")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { onDone() }
            }
        }
        .task {
            prepareReportIfNeeded()
        }
    }

    private func prepareReportIfNeeded() {
        guard preparedReport == nil else { return }
        preparedReport = PositivityTokenStepPreparation.prepare(
            preTokenReport: preTokenReport,
            allTokens: tokens
        )
    }
}

struct PositivityTokenStepPreparedReport {
    let finalReport: [CommitmentReport]
    let usageSummary: PositivityTokenUsageSummary
}

enum PositivityTokenStepPreparation {
    static func prepare(
        preTokenReport: [CommitmentReport],
        allTokens: [PositivityToken],
        monthlyCap: Int? = nil
    ) -> PositivityTokenStepPreparedReport {
        let finalReport = AfterPositivityTokenReportBuilder.apply(
            to: preTokenReport,
            allTokens: allTokens,
            monthlyCap: monthlyCap
        )
        let usageSummary = AfterPositivityTokenReportBuilder.usageSummary(
            preReport: preTokenReport,
            finalReport: finalReport,
            allTokens: allTokens,
            monthlyCap: monthlyCap
        )
        return PositivityTokenStepPreparedReport(
            finalReport: finalReport,
            usageSummary: usageSummary
        )
    }
}
