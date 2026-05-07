import SwiftData
import SwiftUI

struct FinishedCycleReportView: View {
    let request: FinishedCycleReportRequest
    let onFinished: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var preTokenReportForTokenStep: [CommitmentReport] = []
    @State private var showTokenStep = false

    var body: some View {
        NavigationStack {
            CheckInSummaryStep(
                request: request,
                onNext: { preTokenReport in
                    preTokenReportForTokenStep = preTokenReport
                    showTokenStep = true
                },
                onEmptyReport: {
                    onFinished()
                    dismiss()
                }
            )
                .navigationDestination(isPresented: $showTokenStep) {
                    PositivityTokenStep(
                        preTokenReport: preTokenReportForTokenStep,
                        onDone: {
                            onFinished()
                            dismiss()
                        }
                    )
                }
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
        FinishedCycleReportView(request: request, onFinished: {})
    }
}

#Preview {
    let container = HeatmapPreviewFactory.richHistoryContainer()
    FinishedCycleReportViewPreview()
        .modelContainer(container)
        .environmentObject(CheckInUndoManager())
}
