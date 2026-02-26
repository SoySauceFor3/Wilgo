import SwiftUI
import SwiftData
struct MissedOrSkippedHabitRow: View {
    let item: MissedOrSkippedSlot

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private var timeRangeText: String {
        let start = HabitScheduling.windowStartToday(for: item.slot)
        let end = HabitScheduling.windowEndToday(for: item.slot)
        return "\(formattedTime(start)) – \(formattedTime(end))"
    }

    private var statusText: String {
        switch item.status {
        case .some(.skipped):
            return "Skipped (burned credit)"
        case .some(.completed):
            return "Completed"
        case .none:
            return "Window passed, still possible today"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .some(.skipped):
            return .orange
        case .some(.completed):
            return .green
        case .none:
            return .red
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.habit.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(timeRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
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

struct MissedOrSkippedSlot {
    let habit: Habit
    let slot: HabitSlot
    /// nil = missed (no check-in), .skipped = intentionally skipped today.
    let status: HabitCheckInStatus?
}

#Preview("Missed") {
    let calendar = Calendar.current
    let today = Date()
    let start = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: today) ?? today
    let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: today) ?? today

    let slot = HabitSlot(start: start, end: end, sortOrder: 0)
    let habit = Habit(
        title: "Morning reading",
        slots: [slot],
        skipCreditCount: 3,
        skipCreditPeriod: .weekly
    )

    MissedOrSkippedHabitRow(item: MissedOrSkippedSlot(habit: habit, slot: slot, status: nil))
        .modelContainer(for: [Habit.self, HabitSlot.self, HabitCheckIn.self], inMemory: true)
        .padding()
}

#Preview("Skipped") {
    let calendar = Calendar.current
    let today = Date()
    let start = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: today) ?? today
    let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: today) ?? today

    let slot = HabitSlot(start: start, end: end, sortOrder: 0)
    let habit = Habit(
        title: "Morning reading",
        slots: [slot],
        skipCreditCount: 3,
        skipCreditPeriod: .weekly
    )

    MissedOrSkippedHabitRow(item: MissedOrSkippedSlot(habit: habit, slot: slot, status: .skipped))
        .modelContainer(for: [Habit.self, HabitSlot.self, HabitCheckIn.self], inMemory: true)
        .padding()
}
