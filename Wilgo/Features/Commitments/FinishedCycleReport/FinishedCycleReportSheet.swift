import SwiftUI

struct FinishedCycleReportSheet: View {
    let report: FinishedCycleReport
    @Environment(\.dismiss) private var dismiss

    init(report: FinishedCycleReport) {
        self.report = report
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(report.commitments) { commitment in
                    Section(commitment.commitmentTitle) {
                        ForEach(commitment.cycles) { cycle in
                            HStack(alignment: .top, spacing: 12) {
                                Image(
                                    systemName: cycle.metTarget
                                        ? "checkmark.circle.fill" : "xmark.circle.fill"
                                )
                                .foregroundStyle(cycle.metTarget ? .green : .red)
                                .font(.title3)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(cycle.cycleLabel)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    Text(
                                        "\(cycle.compensatedCheckIns)/\(cycle.targetCheckIns) check-ins"
                                    )
                                    .font(.body)

                                    if cycle.isAidedByPositivityToken {
                                        Label(
                                            "Aided by \(cycle.aidedByPositivityTokenCount) positivity token\(cycle.aidedByPositivityTokenCount == 1 ? "" : "s")",
                                            systemImage: "sparkles"
                                        )
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Finished Cycles Report")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    let week1Start = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 10))!
    let week1End = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 17))!
    let week2Start = week1End
    let week2End = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 24))!
    FinishedCycleReportSheet(
        report: FinishedCycleReport(
            commitments: [
                .init(
                    id: "morning-run",
                    commitmentTitle: "Morning Run",
                    cycles: [
                        .init(
                            id: "morning-run-2026-03-10",
                            actualCheckIns: 12,
                            targetCheckIns: 10,
                            cycleLabel: "Mar 10 - Mar 16",
                            cycleStartPsychDay: week1Start,
                            cycleEndPsychDay: week1End,
                            aidedByPositivityTokenCount: 0
                        ),
                        .init(
                            id: "morning-run-2026-03-17",
                            actualCheckIns: 10,
                            targetCheckIns: 10,
                            cycleLabel: "Mar 17 - Mar 23",
                            cycleStartPsychDay: week2Start,
                            cycleEndPsychDay: week2End,
                            aidedByPositivityTokenCount: 0
                        ),
                    ]
                ),
                .init(
                    id: "read-30-min",
                    commitmentTitle: "Read 30 Minutes",
                    cycles: [
                        .init(
                            id: "read-2026-03",
                            actualCheckIns: 4,
                            targetCheckIns: 7,
                            cycleLabel: "Mar 10 - Mar 16",
                            cycleStartPsychDay: week1Start,
                            cycleEndPsychDay: week1End,
                            aidedByPositivityTokenCount: 1
                        )
                    ]
                ),
            ]
        )
    )
}
