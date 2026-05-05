import SwiftUI

/// Step 2 of the FinishedCycleReport flow.
/// Shows every cycle's final outcome after positivity token compensation —
/// identical layout to the original single-page report but without the
/// check-in history expand control.
///
/// Accepts `commitments` by value: re-renders automatically whenever the parent
/// passes a freshly-built report.
struct PositivityTokenPage: View {
    let commitmentReports: [CommitmentReport]
    let usageSummary: PositivityTokenUsageSummary?

    private var totalTokensUsed: Int {
        usageSummary?.totalTokensUsed ??
            commitmentReports
                .flatMap(\.cycles)
                .reduce(0) { $0 + $1.aidedByPositivityTokenCount }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        "\(totalTokensUsed) positivity token\(totalTokensUsed == 1 ? "" : "s") used",
                        systemImage: "sparkles"
                    )
                    .foregroundStyle(totalTokensUsed > 0 ? .blue : .secondary)
                    .font(.subheadline)

                    if let usageSummary {
                        AvailabilityTransitionRow(
                            title: "Available PTs",
                            before: usageSummary.activeTokensBefore,
                            after: usageSummary.activeTokensAfter
                        )
                        AvailabilityTransitionRow(
                            title: "Available budget",
                            before: usageSummary.availableBudgetBefore,
                            after: usageSummary.availableBudgetAfter
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            ForEach(commitmentReports) { report in
                Section(report.commitment.title) {
                    ForEach(report.cycles) { cycle in
                        CycleResultRow(cycle: cycle)
                    }
                }
            }
        }
    }
}

// MARK: - AvailabilityTransitionRow

private struct AvailabilityTransitionRow: View {
    let title: String
    let before: Int
    let after: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(before)")
                .fontWeight(.medium)
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(after)")
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

// MARK: - CycleResultRow

private struct CycleResultRow: View {
    let cycle: CycleReport

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if cycle.isGrace {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(.secondary)
                    .font(.title3)
                    .frame(width: 24)
            } else if !cycle.isTargetEnabled {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.tertiary)
                    .font(.title3)
                    .frame(width: 24)
            } else {
                Image(
                    systemName: cycle.metTarget
                        ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundStyle(cycle.metTarget ? .green : .red)
                .font(.title3)
                .frame(width: 24)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(cycle.cycleLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if cycle.isGrace {
                    Text("\(cycle.actualCheckIns)/\(cycle.targetCheckIns) check-ins · grace")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else if !cycle.isTargetEnabled {
                    Text("\(cycle.actualCheckIns) check-ins · no target")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("\(cycle.compensatedCheckIns)/\(cycle.targetCheckIns) check-ins")
                        .font(.body)
                }

                if cycle.isAidedByPositivityToken {
                    Text(reasonsCopy(for: cycle.consumedPTReasons))
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func reasonsCopy(for reasons: [String]) -> String {
        let lines = reasons.map { "• \($0)" }.joined(separator: "\n")
        return "Missing this commitment is compensated by your Positivity Tokens:\n\(lines)"
    }
}
