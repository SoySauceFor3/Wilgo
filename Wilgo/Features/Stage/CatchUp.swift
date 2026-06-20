import SwiftData
import SwiftUI

struct CatchUpCommitmentRow: View {
    @Bindable var commitment: Commitment
    /// For catch-up, these are the "next up" slots for this commitment.
    let slotOccurences: [SlotOccurrence]
    /// Pre-computed by `StageViewModel`; avoids re-running `status` per row.
    let behindCount: Int
    var onTap: () -> Void

    var body: some View {
        CommitmentStatsCard(
            commitment: commitment,
            slotOccurences: slotOccurences,
            topRightTitle: "Next up Slots"
        ) {
            let count = slotOccurences.count
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    "\(count) " + (count <= 1 ? "slot" : "slots")
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
        cycle: Cycle.makeDefault(.daily),
        slots: [slot],
        target: Target(count: 1),
    )

    let occurrence = slot.occurrence(on: Time.startOfDay(for: today))!
    CatchUpCommitmentRow(
        commitment: commitment, slotOccurences: [occurrence], behindCount: 0, onTap: {}
    )
    .modelContainer(
        for: [Commitment.self, Slot.self, CheckIn.self], inMemory: true
    )
    .padding()
    .environmentObject(CheckInUndoManager())
}
