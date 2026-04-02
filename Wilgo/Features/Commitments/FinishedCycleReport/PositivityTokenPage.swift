import SwiftUI

/// Step 2 of the FinishedCycleReport flow.
/// Shows every cycle's final outcome after positivity token compensation —
/// identical layout to the original single-page report but without the
/// check-in history expand control.
///
/// Accepts `report` by value: re-renders automatically whenever the parent
/// passes a freshly-built report.
struct PositivityTokenPage: View {
    let report: FinishedCycleReport

    private var totalTokensUsed: Int {
        report.commitments
            .flatMap(\.cycles)
            .reduce(0) { $0 + $1.aidedByPositivityTokenCount }
    }

    var body: some View {
        List {
            Section {
                Label(
                    "\(totalTokensUsed) positivity token\(totalTokensUsed == 1 ? "" : "s") used",
                    systemImage: "sparkles"
                )
                .foregroundStyle(totalTokensUsed > 0 ? .blue : .secondary)
                .font(.subheadline)
                .padding(.vertical, 2)
            }
            ForEach(report.commitments) { commitment in
                Section(commitment.commitmentTitle) {
                    ForEach(commitment.cycles) { cycle in
                        CycleResultRow(cycle: cycle)
                    }
                }
            }
        }
    }
}

// MARK: - CycleResultRow

private struct CycleResultRow: View {
    let cycle: FinishedCycleReport.CycleReport

    var body: some View {
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
        }
        .padding(.vertical, 2)
    }
}
