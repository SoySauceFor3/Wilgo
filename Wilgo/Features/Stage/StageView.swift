//  The Stage — dynamic dashboard highlighting the in-window habit with phase-based styling.
//  Schedule: N× daily; each slot has its own ideal window.
//

import SwiftData
import SwiftUI

struct StageView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LiveActivityManager.self) private var liveActivityManager
    @Query(sort: \Habit.createdAt, order: .forward) private var habits: [Habit]
    @Query private var snoozedSlots: [SnoozedSlot]
    /// Advances to the current time at each slot boundary so the Stage re-renders precisely when state changes.
    @State private var timeTick: Date = Date()

    private var stageState: StageState {
        StageEngine.makeState(
            habits: habits,
            snoozedSlots: snoozedSlots,
            now: timeTick
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if !stageState.currentHabitSlots.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Current")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(stageState.currentHabitSlots, id: \.1.id) { habit, slot in
                                CurrentHabitRow(habit: habit, slot: slot)
                            }
                        }
                    }

                    if !stageState.upcomingHabitSlots.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Upcoming")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(stageState.upcomingHabitSlots, id: \.1.id) { habit, slot in
                                UpcomingHabitRow(habit: habit, slot: slot)
                            }
                        }
                    }

                    if !stageState.missedSlots.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Missed / skipped today")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(stageState.missedSlots, id: \.slot.id) { item in
                                MissedHabitRow(item: item)
                            }
                        }
                    }

                    if stageState.currentHabitSlots.isEmpty && stageState.upcomingHabitSlots.isEmpty
                        && stageState.missedSlots.isEmpty
                    {
                        EmptyStageCard()
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stage")
            .task(id: stageState.nextTransitionDate) {
                let target = stageState.nextTransitionDate
                let delay = target.timeIntervalSince(Date())
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                timeTick = Date()
            }
            .onAppear {
                timeTick = Date()
            }
            .onChange(of: stageState.firstLiveActivityContentState) { _, _ in
                liveActivityManager.sync()
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
