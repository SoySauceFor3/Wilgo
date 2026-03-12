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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statsSection
                    heatmapSection
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

    // MARK: - Stats

    private var statsSection: some View {
        HStack(spacing: 10) {
            statTile(
                value: "\(commitment.checkIns.count)",
                label: "All-time\ncheck-ins"
            )
            statTile(
                value: "\(commitment.goalCountPerDay)×",
                label: "Daily\ngoal"
            )
            statTile(
                value: daysTracked,
                label: "Days\ntracked"
            )
        }
    }

    private var daysTracked: String {
        let days =
            Calendar.current
            .dateComponents([.day], from: commitment.createdAt, to: CommitmentScheduling.now())
            .day ?? 0
        return "\(max(1, days + 1))"
    }

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

    // MARK: - Heatmap section

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.headline)
            CommitmentHeatmapView(commitment: commitment)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
