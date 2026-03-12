import SwiftData
import SwiftUI

struct CatchUpCommitmentRow: View {
    @Bindable var commitment: Commitment
    /// For catch-up, these are the "next up" slots for this commitment.
    let slots: [Slot]
    @State private var isPresentingDetail = false
    @State private var isPresentingEdit = false

    var body: some View {
        CommitmentStatsCard(
            commitment: commitment,
            slots: slots,
            topRightTitle: "Next up Slots"
        ) {
            let count = slots.count
            Text(
                count == 0
                    ? "whole day"
                    : "\(count) " + (count == 1 ? "slot" : "slots")
            )
            .font(.caption2)
            .foregroundStyle(.primary)
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
    let end = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: today) ?? today

    let slot = Slot(start: start, end: end)
    let commitment = Commitment(
        title: "Morning reading",
        slots: [slot],
        target: Target(cycle: .daily, countPerCycle: 1),
        skipBudget: SkipBudget(cycle: .weekly(weekday: 2), countPerCycle: 3),
    )

    CatchUpCommitmentRow(commitment: commitment, slots: [slot])
        .modelContainer(
            for: [Commitment.self, Slot.self, CheckIn.self], inMemory: true
        )
        .padding()
}
