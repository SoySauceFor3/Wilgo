import SwiftData
import SwiftUI

struct CommitmentRowView: View {
    @Bindable var commitment: Commitment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top line: status + title
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(commitment.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()
            }

            // Second line: schedule (N× daily)
            HStack(spacing: 4) {
                Label("Schedule", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(commitment.target.count)× \(commitment.target.cycle.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Third line: ideal windows (one per slot)
            HStack(spacing: 4) {
                Label("Windows", systemImage: "sun.max")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(slotWindowsSummary(commitment))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Fourth line: skip credits + proof-of-work
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Label("Skip", systemImage: "arrow.uturn.left")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let budget = commitment.skipBudget
                    Text("\(budget.count) / \(budget.cycle.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(commitment.proofOfWorkType.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.1))
                    )
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func formattedTime(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func slotWindowsSummary(_ commitment: Commitment) -> String {
        return commitment.slots.map {
            "\(formattedTime(from: $0.start))–\(formattedTime(from: $0.end))"
        }
        .joined(separator: ", ")
    }
}
