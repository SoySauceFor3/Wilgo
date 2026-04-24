import SwiftData
import SwiftUI

struct CurrentCommitmentRow: View {
    @Bindable var commitment: Commitment
    let slots: [Slot]
    /// Pre-computed by `StageViewModel`; avoids re-running `stageStatus` per row.
    let behindCount: Int
    @Environment(\.modelContext) private var modelContext
    var onTap: () -> Void

    var body: some View {
        CommitmentStatsCard(
            commitment: commitment,
            slots: slots,
            topRightTitle: "Current Slot",
            onSnooze: snoozeCurrentSlot
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(slots.first?.timeOfDayText ?? "No slot")
                    .font(.caption2)
                    .foregroundStyle(.primary)

                let remaining = max(0, slots.count - 1)
                Text(
                    remaining == 1
                        ? "Next Up: 1 slot"
                        : "Next Up: \(remaining) slots"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                if commitment.target.isEnabled && behindCount > 0 {
                    Text(
                        behindCount == 1
                            ? "Behind"
                            : "Behind +\(behindCount)"
                    )
                    .font(.caption2)
                    .foregroundStyle(.red)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private func snoozeCurrentSlot() {
        // slots[0] is the original Slot model object from stageStatus.nextUpSlots.
        // However, stageStatus returns resolved Slot copies (concrete datetimes) not the
        // original SwiftData objects. We match back by looking for the original slot whose
        // time-of-day window contains now.
        let now = Time.now()
        guard let originalSlot = commitment.slots.first(where: { $0.isActive(on: now) }) else {
            return
        }
        SlotSnooze.create(slot: originalSlot, at: now, in: modelContext)
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
        cycle: Cycle.anchored(.daily, at: .now),
        slots: [slot],
        target: Target(count: 1),
    )

    CurrentCommitmentRow(commitment: commitment, slots: [slot], behindCount: 0, onTap: {})
        .modelContainer(
            for: [Commitment.self, Slot.self, CheckIn.self], inMemory: true
        )
        .padding()
        .environmentObject(CheckInUndoManager())
}
