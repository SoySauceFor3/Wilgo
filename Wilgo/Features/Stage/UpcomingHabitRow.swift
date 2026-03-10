import SwiftData
import SwiftUI

struct UpcomingHabitRow: View {
    let habit: Habit
    let slots: [Slot]

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.title)
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

    return UpcomingHabitRow(habit: habit, slots: [slot])
        .modelContainer(
            for: [Habit.self, Slot.self, HabitCheckIn.self, SnoozedSlot.self], inMemory: true
        )
        .padding()
}
