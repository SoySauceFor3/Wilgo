import SwiftData
import SwiftUI

struct CatchUpHabitRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var habit: Habit
    let slots: [Slot]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.accentColor)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(habit.title)
                        .font(.headline)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        let checkIn = HabitCheckIn(
                            habit: habit,
                        )
                        modelContext.insert(checkIn)
                        habit.checkIns.append(checkIn)  // keep inverse in sync immediately, as inverse relationship propogation takes time.
                    }
                } label: {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }

            HStack {
                Text("Skip credits:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(habit.skipCreditCount) left")
                    .font(.caption2)
                    .fontWeight(.medium)
            }

            Text(
                "\(habit.completedCount(for: HabitScheduling.psychDay(for: HabitScheduling.now())))/\(habit.goalCountPerDay) done today"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text("next up slots: \(slots.map { $0.slotTimeText }.joined(separator: ", "))")
                .font(.caption2)
                .foregroundStyle(.secondary)

        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.accentColor.opacity(0.08))
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

    CatchUpHabitRow(habit: habit, slots: [slot])
        .modelContainer(
            for: [Habit.self, Slot.self, HabitCheckIn.self, SnoozedSlot.self], inMemory: true
        )
        .padding()
}
