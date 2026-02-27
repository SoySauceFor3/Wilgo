import Foundation
import SwiftData
import SwiftUI

struct MissedHabitRow: View {
    let item: MissedHabit

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

    private var overdueText: String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        formatter.maximumUnitCount = 2

        let interval = item.overdueBy
        guard interval > 0,
            let components = formatter.string(from: interval)
        else {
            return "just now overdue"
        }

        return "\(components) overdue"
    }

    private var statusText: String {
        let totalSoFar = item.completedCount + item.missedCount
        return
            "\(item.completedCount)/\(totalSoFar) done, \(item.missedCount) missed · \(overdueText)"
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
                    .foregroundStyle(.red)
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
        skipCreditPeriod: .weekly
    )

    MissedHabitRow(
        item: MissedHabit(
            habit: habit,
            slot: slot,
            completedCount: 1,
            missedCount: 2,
            overdueBy: 60 * 60
        )
    )
    .modelContainer(for: [Habit.self, HabitSlot.self, HabitCheckIn.self], inMemory: true)
    .padding()
}
