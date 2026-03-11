import SwiftData
import SwiftUI

struct CatchUpHabitRow: View {
    @Bindable var habit: Habit
    /// For catch-up, these are the "next up" slots for this habit.
    let slots: [Slot]

    var body: some View {
        HabitStatsCard(
            habit: habit,
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
    }
}

#Preview {
    let calendar = Calendar.current
    let today = Date()
    let start = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: today) ?? today
    let end = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: today) ?? today

    let slot = Slot(start: start, end: end)
    let habit = Habit(
        title: "Morning reading",
        slots: [slot],
        skipCreditCount: 3,
        cycle: .weekly(weekday: 2),
        goalCountPerDay: 1
    )

    CatchUpHabitRow(habit: habit, slots: [slot])
        .modelContainer(
            for: [Habit.self, Slot.self, HabitCheckIn.self], inMemory: true
        )
        .padding()
}
