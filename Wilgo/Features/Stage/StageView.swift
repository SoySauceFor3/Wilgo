//  The Stage — dynamic dashboard highlighting the in-window habit with phase-based styling.
//  Schedule: N× daily; each slot has its own ideal window.
//

import Combine
import SwiftData
import SwiftUI

struct StageView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.createdAt, order: .forward) private var habits: [Habit]
    /// Updates every minute so the Stage re-renders as time passes (current/upcoming/missed change).
    @State private var timeTick: Date = Date()

    /// All (habit, slot) pairs whose window currently covers `now` and have not finished all the completes yet.
    private var currentHabitSlots: [(Habit, HabitSlot)] {
        let now = timeTick
        var result: [(Habit, HabitSlot)] = []

        // we just need to calculate the number of checkins and minus this from the total number of slots.
        for habit in habits {
            let psychDay = HabitScheduling.todayPsychDay(now: now)
            let todaysCheckIns = habit.checkIns.filter { $0.pyschDay == psychDay }
            let slots = habit.slots.sorted()
            let n = todaysCheckIns.count
            if n < slots.count {
                // Consider only slots from (n) onward (0-based), so n+1th is at index n
                let remainingSlots = slots.dropFirst(n)
                for slot in remainingSlots {
                    let start = HabitScheduling.windowStartToday(for: slot)
                    let end = HabitScheduling.windowEndToday(for: slot)
                    if start <= now && now <= end {
                        result.append((habit, slot))
                        break  // Only first such slot
                    }
                }
            }
        }

        // Sort by fraction of window remaining: time left / full window length.
        result.sort { lhs, rhs in
            let leftSlot = lhs.1
            let rightSlot = rhs.1

            let leftStart = HabitScheduling.windowStartToday(for: leftSlot)
            let leftEnd = HabitScheduling.windowEndToday(for: leftSlot)
            let rightStart = HabitScheduling.windowStartToday(for: rightSlot)
            let rightEnd = HabitScheduling.windowEndToday(for: rightSlot)

            let leftDuration = max(leftEnd.timeIntervalSince(leftStart), 1)
            let rightDuration = max(rightEnd.timeIntervalSince(rightStart), 1)

            let leftRemaining = max(leftEnd.timeIntervalSince(now), 0)
            let rightRemaining = max(rightEnd.timeIntervalSince(now), 0)

            let leftRatio = leftRemaining / leftDuration
            let rightRatio = rightRemaining / rightDuration

            return leftRatio < rightRatio
        }

        return result
    }

    /// Upcoming (habit, slot) pairs whose window starts later and have not.
    private var upcomingHabitSlots: [(Habit, HabitSlot)] {
        let now = timeTick
        var result: [(Habit, HabitSlot)] = []

        for habit in habits {
            let psychDay = HabitScheduling.todayPsychDay(now: now)
            let todaysCheckIns = habit.checkIns.filter { $0.pyschDay == psychDay }
            let slots = habit.slots.sorted()
            let n = todaysCheckIns.count
            if n < slots.count {
                // Consider only slots from (n) onward (0-based), so n+1th is at index n
                let remainingSlots = slots.dropFirst(n)
                for slot in remainingSlots {
                    let start = HabitScheduling.windowStartToday(for: slot)

                    if now <= start {
                        result.append((habit, slot))
                        break  // Only first such slot
                    }
                }
            }
        }

        result.sort { lhs, rhs in
            lhs.1 < rhs.1
        }
        return result
    }

    /// Habits with at least one slot whose window has already ended today but hasn't been checked in.
    private var missedSlots: [MissedHabit] {
        let now = timeTick
        let psychDay = HabitScheduling.todayPsychDay(now: now)
        var result: [MissedHabit] = []

        for habit in habits {
            let slots = habit.slots.sorted()

            // Slots whose window has fully ended before "now".
            let endedSlots = slots.filter { slot in
                HabitScheduling.windowEndToday(for: slot) <= now
            }

            guard !endedSlots.isEmpty else { continue }

            let todaysCheckIns = habit.checkIns.filter { $0.pyschDay == psychDay }
            let completedCount = todaysCheckIns.count
            let totalSlotsSoFar = endedSlots.count
            let missedCount = max(totalSlotsSoFar - completedCount, 0)

            guard missedCount > 0 else { continue }

            // Use the latest-ended slot for "overdue" display.
            guard let latestSlot = endedSlots.last else { continue }
            let latestEnd = HabitScheduling.windowEndToday(for: latestSlot)
            let overdueBy = max(now.timeIntervalSince(latestEnd), 0)

            result.append(
                MissedHabit(
                    habit: habit,
                    slot: latestSlot,
                    completedCount: completedCount,
                    missedCount: missedCount,
                    overdueBy: overdueBy
                )
            )
        }

        // Show the most overdue habits first.
        result.sort { $0.overdueBy > $1.overdueBy }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if !currentHabitSlots.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Current")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(currentHabitSlots, id: \.1.id) { habit, slot in
                                CurrentHabitRow(habit: habit, slot: slot)
                            }
                        }
                    }

                    if !upcomingHabitSlots.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Upcoming")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(upcomingHabitSlots, id: \.1.id) { habit, slot in
                                UpcomingHabitRow(habit: habit, slot: slot)
                            }
                        }
                    }

                    if !missedSlots.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Missed / skipped today")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(missedSlots, id: \.slot.id) { item in
                                MissedHabitRow(item: item)
                            }
                        }
                    }

                    if currentHabitSlots.isEmpty && upcomingHabitSlots.isEmpty
                        && missedSlots.isEmpty
                    {
                        EmptyStageCard()
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stage")
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                timeTick = Date()
            }
        }
    }
}

// MARK: - Empty state

private struct EmptyStageCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Nothing on stage right now")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Add habits and set their ideal times to see them here.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

// MARK: - Previews

private enum StagePreviewFactory {
    static var multipleHabits: some View {
        let container = try! ModelContainer(
            for: Habit.self, HabitSlot.self, HabitCheckIn.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let calendar = Calendar.current

        func slot(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int) -> HabitSlot {
            HabitSlot(
                start: calendar.date(from: DateComponents(hour: h1, minute: m1)) ?? Date(),
                end: calendar.date(from: DateComponents(hour: h2, minute: m2)) ?? Date()
            )
        }

        let habit1 = Habit(
            title: "habit 1",
            slots: [slot(23, 0, 23, 10)],
            skipCreditCount: 5,
            skipCreditPeriod: .monthly,
            proofOfWorkType: .manual
        )
        let habit2 = Habit(
            title: "habit 2",
            slots: [slot(23, 1, 23, 59)],
            skipCreditCount: 3,
            skipCreditPeriod: .weekly,
            proofOfWorkType: .manual
        )
        let habit3 = Habit(
            title: "habit 3",
            slots: [slot(23, 0, 23, 30)],
            skipCreditCount: 2,
            skipCreditPeriod: .weekly,
            proofOfWorkType: .manual
        )
        habit1.slots.forEach {
            $0.habit = habit1
            ctx.insert($0)
        }
        habit2.slots.forEach {
            $0.habit = habit2
            ctx.insert($0)
        }
        habit3.slots.forEach {
            $0.habit = habit3
            ctx.insert($0)
        }
        ctx.insert(habit1)
        ctx.insert(habit2)
        ctx.insert(habit3)

        return StageView()
            .modelContainer(container)
    }

    static var singleHabit: some View {
        let container = try! ModelContainer(
            for: Habit.self, HabitSlot.self, HabitCheckIn.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let calendar = Calendar.current
        let slot = HabitSlot(
            start: calendar.date(from: DateComponents(hour: 0, minute: 0)) ?? Date(),
            end: calendar.date(from: DateComponents(hour: 0, minute: 10)) ?? Date()
        )
        let habit = Habit(
            title: "Workout",
            slots: [slot],
            skipCreditCount: 5,
            skipCreditPeriod: .monthly,
            proofOfWorkType: .manual
        )
        slot.habit = habit
        ctx.insert(slot)
        ctx.insert(habit)

        return StageView()
            .modelContainer(container)
    }

    static var empty: some View {
        StageView()
            .modelContainer(
                try! ModelContainer(
                    for: Habit.self, HabitSlot.self, HabitCheckIn.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            )
    }
}

#Preview("Stage with multiple habits") {
    StagePreviewFactory.multipleHabits
}

#Preview("Stage with 1 habit") {
    StagePreviewFactory.singleHabit
}

#Preview("Stage empty") {
    StagePreviewFactory.empty
}
