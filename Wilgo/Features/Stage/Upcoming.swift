import SwiftData
import SwiftUI

struct UpcomingCommitmentRow: View {
    let commitment: Commitment
    let slots: [Slot]
    @State private var isPresentingDetail = false
    @State private var isPresentingEdit = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(commitment.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(slots[0].slotTimeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
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
        skipBudget: SkipBudget(cycle: .weekly(weekday: 2), countPerCycle: 3),
        goalCountPerDay: 1
    )

    return UpcomingCommitmentRow(commitment: commitment, slots: [slot])
        .modelContainer(
            for: [Commitment.self, Slot.self, CheckIn.self], inMemory: true
        )
        .padding()
}
