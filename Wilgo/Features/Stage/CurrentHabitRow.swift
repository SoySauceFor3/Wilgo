import SwiftData
import SwiftUI

struct CurrentHabitRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var habit: Habit
    let slot: HabitSlot

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private var timeRangeText: String {
        let start = slot.startToday
        let end = slot.endToday
        return "\(formattedTime(start)) – \(formattedTime(end))"
    }

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
                    Text(timeRangeText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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

                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        let snooze = SnoozedSlot(
                            habit: habit,
                            slot: slot
                        )
                        modelContext.insert(snooze)
                    }
                } label: {
                    Label("Snooze", systemImage: "flame")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .disabled(habit.skipCreditCount <= 0)
            }

            HStack {
                Text("Skip credits:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(habit.skipCreditCount) left")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
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

    let slot = HabitSlot(start: start, end: end)
    let habit = Habit(
        title: "Morning reading",
        slots: [slot],
        skipCreditCount: 3,
        cycle: .weekly(weekday: 2),
        goalCountPerDay: 1
    )

    CurrentHabitRow(habit: habit, slot: slot)
        .modelContainer(
            for: [Habit.self, HabitSlot.self, HabitCheckIn.self, SnoozedSlot.self], inMemory: true
        )
        .padding()
}

#Preview("Gentle (in window)") {
    let calendar = Calendar.current
    let now = Date()
    let start = calendar.date(byAdding: .minute, value: -30, to: now) ?? now
    let end = calendar.date(byAdding: .minute, value: 30, to: now) ?? now

    let slot = HabitSlot(start: start, end: end)
    let habit = Habit(
        title: "Gentle: read 10 pages",
        slots: [slot],
        skipCreditCount: 3,
        cycle: .weekly(weekday: 2),
        goalCountPerDay: 1
    )

    CurrentHabitRow(habit: habit, slot: slot)
        .modelContainer(
            for: [Habit.self, HabitSlot.self, HabitCheckIn.self, SnoozedSlot.self], inMemory: true
        )
        .padding()
}

#Preview("Judgmental (window passed)") {
    let calendar = Calendar.current
    let now = Date()
    let start = calendar.date(byAdding: .hour, value: -3, to: now) ?? now
    let end = calendar.date(byAdding: .hour, value: -2, to: now) ?? now

    let slot = HabitSlot(start: start, end: end)
    let habit = Habit(
        title: "Judgmental: afternoon walk",
        slots: [slot],
        skipCreditCount: 2,
        cycle: .weekly(weekday: 2),
        goalCountPerDay: 1
    )

    return CurrentHabitRow(habit: habit, slot: slot)
        .modelContainer(
            for: [Habit.self, HabitSlot.self, HabitCheckIn.self, SnoozedSlot.self], inMemory: true
        )
        .padding()
}

#Preview("Critical (late in day)") {
    let calendar = Calendar.current
    let now = Date()
    let startComponents = calendar.dateComponents(
        [.hour, .minute], from: now.addingTimeInterval(-5 * 60 * 60))
    let endComponents = calendar.dateComponents(
        [.hour, .minute], from: now.addingTimeInterval(-4 * 60 * 60))
    let start = calendar.date(from: startComponents) ?? now
    let end = calendar.date(from: endComponents) ?? now

    let slot = HabitSlot(start: start, end: end)
    let habit = Habit(
        title: "Critical: submit report",
        slots: [slot],
        skipCreditCount: 1,
        cycle: .weekly(weekday: 2),
        goalCountPerDay: 1
    )

    return CurrentHabitRow(habit: habit, slot: slot)
        .modelContainer(
            for: [Habit.self, HabitSlot.self, HabitCheckIn.self, SnoozedSlot.self], inMemory: true
        )
        .padding()
}

#Preview("Settled (not active)") {
    let calendar = Calendar.current
    let now = Date()
    let start = calendar.date(byAdding: .hour, value: 3, to: now) ?? now
    let end = calendar.date(byAdding: .hour, value: 4, to: now) ?? now

    let slot = HabitSlot(start: start, end: end)
    let habit = Habit(
        title: "Settled: late workout",
        slots: [slot],
        skipCreditCount: 4,
        cycle: .weekly(weekday: 2),
        goalCountPerDay: 1
    )

    return CurrentHabitRow(habit: habit, slot: slot)
        .modelContainer(
            for: [Habit.self, HabitSlot.self, HabitCheckIn.self, SnoozedSlot.self], inMemory: true
        )
        .padding()
}
