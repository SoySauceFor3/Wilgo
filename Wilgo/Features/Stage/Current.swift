import SwiftData
import SwiftUI

struct CurrentCommitmentRow: View {
    @Bindable var commitment: Commitment
    let slots: [Slot]
    @State private var isPresentingDetail = false
    @State private var isPresentingEdit = false

    var body: some View {
        CommitmentStatsCard(
            commitment: commitment,
            slots: slots,
            topRightTitle: "Current Slot"
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(slots.first?.slotTimeText ?? "No slot")
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
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isPresentingDetail = true
        }
        .sheet(isPresented: $isPresentingDetail) {
            CommitmentDetailView(commitment: commitment) {
                isPresentingDetail = false
                isPresentingEdit = true
            }
            .presentationDetents([.fraction(0.65), .large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $isPresentingEdit) {
            NavigationStack {
                EditCommitmentView(commitment: commitment)
            }
        }
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
        slots: [slot],
        skipCreditCount: 3,
        cycle: .weekly(weekday: 2),
        goalCountPerDay: 1
    )

    CurrentCommitmentRow(commitment: commitment, slots: [slot])
        .modelContainer(
            for: [Commitment.self, Slot.self, CheckIn.self], inMemory: true
        )
        .padding()
}
