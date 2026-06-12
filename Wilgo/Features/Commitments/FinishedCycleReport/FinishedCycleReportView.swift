import SwiftData
import SwiftUI

struct FinishedCycleReportView: View {
    let request: FinishedCycleReportRequest
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Commitment.createdAt, order: .forward) private var commitments: [Commitment]

    /// Per-cycle editable state, keyed by `CycleReport.id`. Persists across
    /// re-renders as backfills mutate the live report.
    @State private var cardStates: [String: FCRCycleCardState] = [:]

    private var report: [CommitmentReport] {
        PreTokenReportBuilder.build(
            commitments: commitments,
            startPsychDay: request.startPsychDay,
            endPsychDay: request.endPsychDay
        )
    }

    private var allCycles: [(commitment: Commitment, cycle: CycleReport)] {
        report.flatMap { cr in cr.cycles.map { (cr.commitment, $0) } }
    }

    private var canClose: Bool {
        FCRCompletion.canClose(states: Array(cardStates.values))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(allCycles, id: \.cycle.id) { pair in
                        if let binding = stateBinding(for: pair.cycle) {
                            FCRCycleCardView(
                                cycle: pair.cycle,
                                commitment: pair.commitment,
                                state: binding
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Cycle Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onFinished()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onFinished()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canClose)
                }
            }
            .overlay(alignment: .bottom) {
                CheckInUndoBannerOverlay()
            }
            .onAppear(perform: reconcileStates)
            .onChange(of: report.map { $0.cycles.map(\.id) }) { _, _ in
                reconcileStates()
            }
            .onChange(of: checkInCountSignature) { _, _ in
                reconcileStates()
            }
            .onAppear {
                if report.isEmpty {
                    onFinished()
                    dismiss()
                }
            }
        }
    }

    /// A signature that changes whenever any cycle's check-in count changes
    /// (e.g. after backfill), so card states re-sync their counts.
    private var checkInCountSignature: [Int] {
        allCycles.map(\.cycle.actualCheckIns)
    }

    private func stateBinding(for cycle: CycleReport) -> Binding<FCRCycleCardState>? {
        guard cardStates[cycle.id] != nil else { return nil }
        return Binding(
            get: { cardStates[cycle.id] ?? FCRCycleCardState(targetCount: cycle.targetCheckIns, checkInCount: cycle.actualCheckIns) },
            set: { cardStates[cycle.id] = $0 }
        )
    }

    /// Create missing card states and push live check-in counts into existing
    /// ones. The count setter on `FCRCycleCardState` handles the failed→passed
    /// flip automatically.
    private func reconcileStates() {
        for (_, cycle) in allCycles {
            if var existing = cardStates[cycle.id] {
                if existing.checkInCount != cycle.actualCheckIns {
                    existing.checkInCount = cycle.actualCheckIns
                    cardStates[cycle.id] = existing
                }
            } else {
                cardStates[cycle.id] = FCRCycleCardState(
                    targetCount: cycle.targetCheckIns,
                    checkInCount: cycle.actualCheckIns
                )
            }
        }
        // Drop states for cycles no longer present.
        let liveIDs = Set(allCycles.map(\.cycle.id))
        for key in cardStates.keys where !liveIDs.contains(key) {
            cardStates[key] = nil
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
