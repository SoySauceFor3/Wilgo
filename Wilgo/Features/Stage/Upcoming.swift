import SwiftData
import SwiftUI

struct UpcomingCommitmentRow: View {
    let commitment: Commitment
    let slots: [Slot]
    /// Pre-computed by `StageViewModel`; avoids re-running `stageStatus` per row.
    let behindCount: Int
    @State private var isPresentingDetail = false
    @State private var isPresentingEdit = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(commitment.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(slots[0].timeOfDayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if behindCount > 0 {
                Text(
                    behindCount == 1
                        ? "Behind"
                        : "Behind +\(behindCount)"
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
        target: Target(cycle: Cycle.anchored(.daily, at: .now), count: 1),
    )

    return UpcomingCommitmentRow(commitment: commitment, slots: [slot], behindCount: 0)
        .modelContainer(
            for: [Commitment.self, Slot.self, CheckIn.self], inMemory: true
        )
        .padding()
}
