import SwiftData
import SwiftUI

struct CurrentHabitRow: View {
    @Bindable var habit: Habit
    let slots: [Slot]
    @State private var isPresentingDetail = false

    var body: some View {
        HabitStatsCard(
            habit: habit,
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
            HabitDetailView(habit: habit)
                .presentationDetents([.fraction(0.65), .large])
                .presentationDragIndicator(.visible)
        }
    }
}

#Preview {
    let calendar = Calendar.current
    let today = Date()
    let start = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: today) ?? today
    let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: today) ?? today

    let slot = Slot(start: start, end: end)
    let habit = Habit(
        title: "Morning reading",
        slots: [slot],
        skipCreditCount: 3,
        cycle: .weekly(weekday: 2),
        goalCountPerDay: 1
    )

    CurrentHabitRow(habit: habit, slots: [slot])
        .modelContainer(
            for: [Habit.self, Slot.self, HabitCheckIn.self], inMemory: true
        )
        .padding()
}
