import SwiftData
import SwiftUI

struct UpcomingCommitmentRow: View {
    /// Pre-computed by `StageBucketing`; carries the nearest slot + the data the row needs
    /// (avoids re-running `status` per row).
    let characteristics: CommitmentCharacteristics
    var onTap: () -> Void

    private var commitment: Commitment { characteristics.commitment }

    /// "+k more" count: usable slots remaining in the cycle *besides* the headline one shown above.
    /// `max(0, …)` so it never goes negative; the row shows the badge only when > 0.
    private var extraCount: Int { max(0, characteristics.remainingThisCycleCount - 1) }  // -1 because this is a number for "+k" so the one shown does not count.

    /// The time line under the title (PRD §9): for a current-cycle nearest slot, its time-of-day
    /// plus "+k more" when other usable slots remain this cycle; for a future-cycle slot, its exact
    /// dated window tagged "future cycle".
    @ViewBuilder
    private var timeLine: some View {
        if let nearest = characteristics.nearestUsable {
            if characteristics.nearestUsableInCurrentCycle {
                HStack(spacing: 6) {
                    Text(nearest.timeOfDayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if extraCount > 0 {
                        Text("+\(extraCount) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Text(nearest.datedLabel)
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
            if commitment.target.configuredMode != .disabled, characteristics.behindCount > 0 {
                Text(
                    characteristics.behindCount == 1
                        ? "Behind"
                        : "Behind +\(characteristics.behindCount)"
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
    let currentEntry = CommitmentCharacteristics(
        commitment: commitment,
        currentOccurrence: nil,
        remainingThisCycleCount: 3,
        nearestUsable: occurrence,
        nearestUsableInCurrentCycle: true,
        behindCount: 0,
        checkInCount: 0,
        targetCount: 1
    )
    // Future-cycle row → exact datetime + "future cycle" marker.
    let futureEntry = CommitmentCharacteristics(
        commitment: commitment,
        currentOccurrence: nil,
        remainingThisCycleCount: 0,
        nearestUsable: occurrence,
        nearestUsableInCurrentCycle: false,
        behindCount: 0,
        checkInCount: 0,
        targetCount: 1
    )
    VStack {
        UpcomingCommitmentRow(characteristics: currentEntry, onTap: {})
        UpcomingCommitmentRow(characteristics: futureEntry, onTap: {})
    }
    .modelContainer(
        for: [Commitment.self, Slot.self, CheckIn.self], inMemory: true
    )
    .padding()
}
