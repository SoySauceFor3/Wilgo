import SwiftData
import SwiftUI

struct CommitmentRowView: View {
    enum Variant {
        case list
        case settings
    }

    @Bindable var commitment: Commitment
    var variant: Variant = .list

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top line
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                switch variant {
                case .list:
                    Text(commitment.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                case .settings:
                    Text("Settings")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                Spacer()
            }

            HStack(spacing: 4) {
                Label("Reminder windows", systemImage: "sun.max")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(commitment.isRemindersEnabled ? slotWindowsSummary(commitment) : "Disabled")
                    .font(.caption)
                    .foregroundStyle(commitment.isRemindersEnabled ? .secondary : .tertiary)
            }

            HStack(spacing: 4) {
                Label("Target", systemImage: "target")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if commitment.target.isEnabled {
                    Text("\(commitment.target.count)× \(commitment.cycle.kind.adj)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Fifth line: skip credits + proof-of-work
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Label("Punishment", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let punishment = commitment.punishment
                    Text((punishment != nil && !punishment!.isEmpty) ? "\(punishment!)" : "None")
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

            if !commitment.tags.isEmpty {
                Text(commitment.tags.sorted { $0.displayOrder < $1.displayOrder || ($0.displayOrder == $1.displayOrder && $0.createdAt < $1.createdAt) }
                    .map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func slotWindowsSummary(_ commitment: Commitment) -> String {
        return commitment.slots.map {
            $0.label
        }
        .joined(separator: "\n")
    }
}
