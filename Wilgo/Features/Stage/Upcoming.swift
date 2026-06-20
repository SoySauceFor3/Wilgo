import SwiftData
import SwiftUI

struct UpcomingCommitmentRow: View {
    let commitment: Commitment
    let slots: [SlotOccurrence]
    /// Pre-computed by `StageViewModel`; avoids re-running `status` per row.
    let behindCount: Int
    var onTap: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(commitment.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(slots[0].timeOfDayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if commitment.target.configuredMode != .disabled, behindCount > 0 {
                Text(
                    behindCount == 1
                        ? "Behind"
                        : "Behind +\(behindCount)"
                )
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.red.opacity(0.12))
                )
                .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

#Preview {
    let calendar = Calendar.current
    let today = Date()
    let start = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: today) ?? today
    let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: today) ?? today

    let slot = Slot(start: start, end: end)
    let commitment = Commitment(
        title: "Morning reading",
        cycle: Cycle.makeDefault(.daily),
        slots: [slot],
        target: Target(count: 1),
    )

    let occurrence = slot.occurrence(on: Time.startOfDay(for: today))!
    UpcomingCommitmentRow(commitment: commitment, slots: [occurrence], behindCount: 0, onTap: {})
        .modelContainer(
            for: [Commitment.self, Slot.self, CheckIn.self], inMemory: true
        )
        .padding()
}
