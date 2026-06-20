import SwiftData
import SwiftUI

struct CurrentCommitmentRow: View {
    @Bindable var commitment: Commitment
    let slots: [SlotOccurrence]
    /// Pre-computed by `StageViewModel`; avoids re-running `status` per row.
    let behindCount: Int
    @Environment(\.modelContext) private var modelContext
    var onTap: () -> Void

    var body: some View {
        CommitmentStatsCard(
            commitment: commitment,
            slotOccurences: slots,
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

                if commitment.target.configuredMode != .disabled, behindCount > 0 {
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
        // slots[0] is the original Slot model object from status.remainingSlots.
        // However, slotStatus returns resolved Slot copies (concrete datetimes) not the
        // original SwiftData objects. We match back by looking for the original slot whose
        // time-of-day window contains now.
        let now = Time.now()
        guard let originalSlot = commitment.slots.first(where: { $0.isScheduled(on: now) }) else {
            return
        }
        originalSlot.snooze(at: now, in: modelContext)
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
    CurrentCommitmentRow(commitment: commitment, slots: [occurrence], behindCount: 0, onTap: {})
        .modelContainer(
            for: [Commitment.self, Slot.self, CheckIn.self], inMemory: true
        )
        .padding()
        .environmentObject(CheckInUndoManager())
}
