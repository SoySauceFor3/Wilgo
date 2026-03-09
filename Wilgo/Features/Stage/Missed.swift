import Foundation
import SwiftData
import SwiftUI

struct MissedHabitRow: View {
    @Environment(\.modelContext) private var modelContext
    let item: MissedHabit

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private var timeRangeText: String {
        let start = item.slot.startToday
        let end = item.slot.endToday
        return "\(formattedTime(start)) – \(formattedTime(end))"
    }

    private var overdueText: String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        formatter.maximumUnitCount = 2

        let interval = item.overdueBy
        guard let components = formatter.string(from: abs(interval)) else {
            return "Invalid interval"
        }
        if interval < 0 {
            return "still in snoozed window, have \(components) to complete"
        } else {
            return "\(components) overdue from last slot"
        }

    }

    private var statusText: String {
        let totalSoFar = item.completedCount + item.missedCount
        return
            "\(item.completedCount)/\(totalSoFar) done · \(overdueText)"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.habit.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(timeRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    let checkIn = HabitCheckIn(habit: item.habit)
                    modelContext.insert(checkIn)
                    item.habit.checkIns.append(checkIn)  // keep inverse in sync immediately, as inverse relationship propogation takes time.
                }
            } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

struct MissedHabit {
    let habit: Habit
    let slot: HabitSlot
    /// Number of check-ins today for this habit.
    let completedCount: Int
    /// Number of missed slots (ended before now without check-ins).
    let missedCount: Int
    /// How long ago the latest-ended missed slot finished.
    let overdueBy: TimeInterval
}

#Preview("Missed") {
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

    MissedHabitRow(
        item: MissedHabit(
            habit: habit,
            slot: slot,
            completedCount: 1,
            missedCount: 2,
            overdueBy: Date().timeIntervalSince(Date().addingTimeInterval(-60 * 60))
        )
    )
    .modelContainer(for: [Habit.self, HabitSlot.self, HabitCheckIn.self, SnoozedSlot.self], inMemory: true)
    .padding()
}

#Preview("Future, but snoozed") {
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

    MissedHabitRow(
        item: MissedHabit(
            habit: habit,
            slot: slot,
            completedCount: 1,
            missedCount: 2,
            overdueBy: Date().timeIntervalSince(Date().addingTimeInterval(60 * 60))
        )
    )
    .modelContainer(for: [Habit.self, HabitSlot.self, HabitCheckIn.self, SnoozedSlot.self], inMemory: true)
    .padding()
}
