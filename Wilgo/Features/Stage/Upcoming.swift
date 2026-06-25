import SwiftData
import SwiftUI

struct UpcomingCommitmentRow: View {
    /// Pre-computed by `StageViewModel`; carries the nearest slot + the data the row needs
    /// (avoids re-running `status` per row).
    let entry: CommitmentAndSlot.UpcomingEntry
    var onTap: () -> Void

    private var commitment: Commitment { entry.commitment }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(commitment.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(entry.nearestSlot.timeOfDayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if commitment.target.configuredMode != .disabled, entry.behindCount > 0 {
                Text(
                    entry.behindCount == 1
                        ? "Behind"
                        : "Behind +\(entry.behindCount)"
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
    let entry = CommitmentAndSlot.UpcomingEntry(
        commitment: commitment,
        nearestSlot: occurrence,
        isInCurrentCycle: true,
        currentCycleRemainingCount: 1,
        behindCount: 0
    )
    UpcomingCommitmentRow(entry: entry, onTap: {})
        .modelContainer(
            for: [Commitment.self, Slot.self, CheckIn.self], inMemory: true
        )
        .padding()
}
