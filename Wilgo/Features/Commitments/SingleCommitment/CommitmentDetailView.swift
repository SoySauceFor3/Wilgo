import SwiftData
import SwiftUI

struct CommitmentDetailView: View {
    let commitment: Commitment
    let onEdit: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingBackfill = false

    init(commitment: Commitment, onEdit: (() -> Void)? = nil) {
        self.commitment = commitment
        self.onEdit = onEdit
    }

    // MARK: - Derived data

    private var psychToday: Date {
        Time.startOfDay(for: Time.now())
    }

    private var checkInsInCurrentTargetCycle: [CheckIn] {
        commitment.checkInsInCycle(
            cycle: commitment.target.cycle, until: psychToday, inclusive: true
        )
    }

    private var daysTracked: String {
        let days =
            Calendar.current
            .dateComponents([.day], from: commitment.createdAt, to: Time.now())
            .day ?? 0
        return "\(max(1, days + 1))"
    }

    private var targetCycleLabel: String {
        commitment.target.cycle.label(of: psychToday)
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
                    backfillButton
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
            .sheet(isPresented: $isPresentingBackfill) {
                BackfillSheet(commitment: commitment)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Backfill

    private var backfillButton: some View {
        Button {
            isPresentingBackfill = true
        } label: {
            Label("Backfill a Check-in", systemImage: "clock.arrow.circlepath")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
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
                    statTile(
                        value:
                            "\(checkInsInCurrentTargetCycle.count)/\(commitment.target.count)",
                        label: "Completed \(commitment.target.cycle.kind.thisNoun)"
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
        fmt.dateFormat = "MM/dd/yy"
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
