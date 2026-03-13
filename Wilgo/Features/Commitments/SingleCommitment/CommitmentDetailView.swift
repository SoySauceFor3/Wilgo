import SwiftData
import SwiftUI

struct CommitmentDetailView: View {
    let commitment: Commitment
    let onEdit: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    init(commitment: Commitment, onEdit: (() -> Void)? = nil) {
        self.commitment = commitment
        self.onEdit = onEdit
    }

    // MARK: - Derived data

    private var psychToday: Date {
        CommitmentScheduling.psychDay(for: CommitmentScheduling.now())
    }

    private var completedToday: Int {
        commitment.completedCount(for: psychToday)
    }

    private var daysTracked: String {
        let days =
            Calendar.current
            .dateComponents([.day], from: commitment.createdAt, to: CommitmentScheduling.now())
            .day ?? 0
        return "\(max(1, days + 1))"
    }

    private var targetCycleLabel: String {
        commitment.target.cycle.label(of: psychToday)
    }

    private var skipCycleLabel: String {
        commitment.skipBudget.cycle.label(of: psychToday)
    }

    private var skipCreditsUsed: Int {
        SkipCredit.creditsUsedInCycle(for: commitment, until: psychToday, inclusive: false)
    }

    private var hasPunishment: Bool {
        if let punishment = commitment.punishment {
            return !punishment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CommitmentRowView(commitment: commitment, variant: .settings)
                    currentSection
                    historySection
                }
                .padding()
            }
            .navigationTitle(commitment.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { onEdit?() }
                }
            }
        }
    }

    // MARK: - Current

    private var currentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current as of \(formattedShortDate(psychToday))")
                .font(.headline)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Check-ins")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(targetCycleLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // TODO: Make this part work for weekly/monthly target
                    statTile(
                        value: "\(completedToday)/\(commitment.target.count)",
                        label: "Completed today"
                    )

                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Skip credits")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(skipCycleLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    statTile(
                        value: "\(skipCreditsUsed)/\(commitment.skipBudget.count)",
                        label: "Credits used"
                    )

                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.headline)

            statsSection

            CommitmentHeatmapView(commitment: commitment)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var statsSection: some View {
        HStack(spacing: 10) {
            statTile(
                value: "\(commitment.checkIns.count)",
                label: "All-time\ncheck-ins"
            )
            statTile(
                value: "\(commitment.target.count)×",
                label: "\(commitment.target.cycle.kind.rawValue)\ngoal"
            )
            statTile(
                value: daysTracked,
                label: "Days tracked\nsince \(formattedShortDate(commitment.createdAt))"
            )
        }
    }

    // MARK: - Tile + formatting helpers

    private func statTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func formattedShortDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return fmt.string(from: date)
    }
}

// MARK: - Previews

#Preview("Rich history") {
    let container = HeatmapPreviewFactory.richHistoryContainer()
    PreviewWithFirstCommitment(container: container) { commitment in
        NavigationStack {
            CommitmentDetailView(commitment: commitment)
        }
    }
}

#Preview("New commitment") {
    let container = HeatmapPreviewFactory.newCommitmentContainer()
    PreviewWithFirstCommitment(container: container) { commitment in
        NavigationStack {
            CommitmentDetailView(commitment: commitment)
        }
    }
}
