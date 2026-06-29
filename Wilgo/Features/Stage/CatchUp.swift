import SwiftData
import SwiftUI

struct CatchUpCommitmentRow: View {
    /// Pre-computed by `StageViewModel`; carries the counts (avoids re-running status).
    let characteristics: CommitmentCharacteristics
    var onTap: () -> Void

    private var commitment: Commitment { characteristics.commitment }
    private var behindCount: Int { characteristics.behindCount }

    var body: some View {
        CommitmentStatsCard(
            commitment: commitment,
            topRightTitle: "Next up Slots"
        ) {
            let count = characteristics.remainingThisCycleCount
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    count == 1 ? "1 slot remaining" : "\(count) slots remaining"
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
    let characteristics = CommitmentCharacteristics(
        commitment: commitment,
        currentOccurrence: nil,
        remainingThisCycleCount: 1,
        nearestUsable: occurrence,
        nearestUsableInCurrentCycle: true,
        behindCount: 2,
        checkInCount: 0,
        targetCount: 3
    )
    CatchUpCommitmentRow(characteristics: characteristics, onTap: {})
        .modelContainer(
        for: [Commitment.self, Slot.self, CheckIn.self], inMemory: true
    )
    .padding()
    .environmentObject(CheckInUndoManager())
}
