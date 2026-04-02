import SwiftUI

struct FinishedCycleReportSheet: View {
    let report: FinishedCycleReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(report.commitments) { commitment in
                    Section(commitment.commitmentTitle) {
                        ForEach(commitment.cycles) { cycle in
                            CycleRow(cycle: cycle)
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

// MARK: - CycleRow

private struct CycleRow: View {
    let cycle: FinishedCycleReport.CycleReport

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(
                    systemName: cycle.metTarget
                        ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundStyle(cycle.metTarget ? .green : .red)
                .font(.title3)
                .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(cycle.cycleLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("\(cycle.compensatedCheckIns)/\(cycle.targetCheckIns) check-ins")
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

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "clock.fill" : "clock")
                        .foregroundStyle(isExpanded ? .primary : .secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)

            if isExpanded {
                checkInHistoryView
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var checkInHistoryView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if cycle.checkIns.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "minus")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("No check-ins recorded")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.leading, 36)
            } else {
                ForEach(cycle.checkIns, id: \.createdAt) { checkIn in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.secondary.opacity(0.35))
                            .frame(width: 5, height: 5)
                        Text(formattedDateTime(checkIn.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 36)
                }
            }
        }
        .padding(.bottom, 6)
    }

    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
                            aidedByPositivityTokenCount: 0,
                            checkIns: []
                        ),
                        .init(
                            id: "morning-run-2026-03-17",
                            actualCheckIns: 10,
                            targetCheckIns: 10,
                            cycleLabel: "Mar 17 - Mar 23",
                            cycleStartPsychDay: week2Start,
                            cycleEndPsychDay: week2End,
                            aidedByPositivityTokenCount: 0,
                            checkIns: []
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
                            aidedByPositivityTokenCount: 1,
                            checkIns: []
                        )
                    ]
                ),
            ]
        )
    )
}
