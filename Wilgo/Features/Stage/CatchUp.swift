import SwiftData
import SwiftUI

struct CatchUpCommitmentRow: View {
    @Bindable var commitment: Commitment
    /// For catch-up, these are the "next up" slots for this commitment.
    let slots: [Slot]
    /// Pre-computed by `StageViewModel`; avoids re-running `stageStatus` per row.
    let behindCount: Int
    var onTap: () -> Void

    var body: some View {
        CommitmentStatsCard(
            commitment: commitment,
            slots: slots,
            topRightTitle: "Next up Slots"
        ) {
            let count = slots.count
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    count == 0
                        ? "whole day"
                        : "\(count) " + (count == 1 ? "slot" : "slots")
                )
                .font(.caption2)
                .foregroundStyle(.primary)

                if behindCount > 0 {
                    Text(
                        "Behind \(behindCount)"
                    )
                    .font(.caption2)
                    .foregroundStyle(.red)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

#Preview {
    let calendar = Calendar.current
    let today = Date()
    let start = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: today) ?? today
    let end = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: today) ?? today

    let slot = Slot(start: start, end: end)
    let commitment = Commitment(
        title: "Morning reading",
        cycle: Cycle.anchored(.daily, at: .now),
        slots: [slot],
        target: Target(count: 1),
    )

    CatchUpCommitmentRow(commitment: commitment, slots: [slot], behindCount: 0, onTap: {})
        .modelContainer(
            for: [Commitment.self, Slot.self, CheckIn.self], inMemory: true
        )
        .padding()
        .environmentObject(CheckInUndoManager())
}
