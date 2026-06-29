import SwiftData
import SwiftUI

struct UpcomingCommitmentRow: View {
    /// Pre-computed by `StageViewModel`; carries the nearest slot + the data the row needs
    /// (avoids re-running `status` per row).
    let entry: CommitmentAndSlot.UpcomingEntry
    var onTap: () -> Void

    private var commitment: Commitment { entry.commitment }

    /// The time line under the title: current-cycle time (+ "+k more"), or a future-cycle
    /// exact datetime tagged "future cycle". Decision comes from `entry.rowDisplay` (PRD §9).
    @ViewBuilder
    private var timeLine: some View {
        switch entry.rowDisplay {
        case let .currentCycle(timeText, extraCount):
            HStack(spacing: 6) {
                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if extraCount > 0 {
                    Text("+\(extraCount) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        case let .futureCycle(dateTimeText):
            HStack(spacing: 6) {
                Text(dateTimeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("future cycle")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    .foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(commitment.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                timeLine
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
    // Current-cycle row with 2 more usable slots this cycle → shows "+2 more".
    let currentEntry = CommitmentAndSlot.UpcomingEntry(
        commitment: commitment,
        nearestSlot: occurrence,
        nearestUsableInCurrentCycle: true,
        currentCycleRemainingCount: 3,
        behindCount: 0
    )
    // Future-cycle row → exact datetime + "future cycle" marker.
    let futureEntry = CommitmentAndSlot.UpcomingEntry(
        commitment: commitment,
        nearestSlot: occurrence,
        nearestUsableInCurrentCycle: false,
        currentCycleRemainingCount: 0,
        behindCount: 0
    )
    VStack {
        UpcomingCommitmentRow(entry: currentEntry, onTap: {})
        UpcomingCommitmentRow(entry: futureEntry, onTap: {})
    }
    .modelContainer(
        for: [Commitment.self, Slot.self, CheckIn.self], inMemory: true
    )
    .padding()
}
