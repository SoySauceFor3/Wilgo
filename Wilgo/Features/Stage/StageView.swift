//  The Stage — dynamic dashboard highlighting the in-window habit with phase-based styling.
//  Schedule: N× daily; each slot has its own ideal window.
//

import SwiftData
import SwiftUI

struct StageView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LiveActivityManager.self) private var liveActivityManager
    @Query(sort: \Habit.createdAt, order: .forward) private var habits: [Habit]
    @Query private var snoozedSlots: [SnoozedSlot]
    /// Observed only to force a re-render when check-ins are inserted/deleted,
    /// since @Query for Habit does not re-fire on child relationship changes.
    @Query private var checkIns: [HabitCheckIn]

    /// actually change the value of it will trigger a rerender.
    @State private var rewrite = false

    private var current: [(Habit, HabitSlot)] {
        HabitAndSlot.current(habits: habits, snoozedSlots: snoozedSlots, now: Date())
    }

    private var upcoming: [(Habit, HabitSlot)] {
        HabitAndSlot.upcoming(habits: habits, now: Date())
    }

    private var missed: [MissedHabit] {
        HabitAndSlot.missed(habits: habits, snoozedSlots: snoozedSlots, now: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if !current.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Current")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(current, id: \.1.id) { habit, slot in
                                CurrentHabitRow(habit: habit, slot: slot)
                            }
                        }
                    }

                    if !upcoming.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Upcoming")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(upcoming, id: \.1.id) { habit, slot in
                                UpcomingHabitRow(habit: habit, slot: slot)
                            }
                        }
                    }

                    if !missed.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Missed / skipped today")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(missed, id: \.slot.id) { item in
                                MissedHabitRow(item: item)
                            }
                        }
                    }

                    if current.isEmpty && upcoming.isEmpty && missed.isEmpty {
                        EmptyStageCard()
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stage")
            .task(id: rewrite) {
                let nextTransitionDate = HabitAndSlot.nextTransitionDate(
                    habits: habits, now: Date())
                let delay = nextTransitionDate?.timeIntervalSince(Date()) ?? 60
                if delay > 0 {
                    try? await Task.sleep(until: .now + .seconds(delay), clock: .continuous)
                }
                rewrite.toggle()
            }
            .onAppear {
                rewrite.toggle()
            }
            .onChange(of: scenePhase) { _, phase in
                // When the app is brought back to the foreground, force a re-render.
                // Not very necessary, just a safety net.
                if phase == .active { rewrite.toggle() }
            }
            .onChange(of: liveActivityManager.makeFirstLiveActivityContentState(from: current)) {
                _, _ in
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
            for: Habit.self, HabitSlot.self, HabitCheckIn.self, SnoozedSlot.self,
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
            cycle: .monthly(day: 1),
            proofOfWorkType: .manual,
            goalCountPerDay: 1
        )
        let habit2 = Habit(
            title: "habit 2",
            slots: [slot(23, 1, 23, 59)],
            skipCreditCount: 3,
            cycle: .weekly(weekday: 2),
            proofOfWorkType: .manual,
            goalCountPerDay: 1
        )
        let habit3 = Habit(
            title: "habit 3",
            slots: [slot(23, 0, 23, 30)],
            skipCreditCount: 2,
            cycle: .weekly(weekday: 2),
            proofOfWorkType: .manual,
            goalCountPerDay: 1
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
            for: Habit.self, HabitSlot.self, HabitCheckIn.self, SnoozedSlot.self,
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
            cycle: .monthly(day: 1),
            proofOfWorkType: .manual,
            goalCountPerDay: 1
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
                    for: Habit.self, HabitSlot.self, HabitCheckIn.self, SnoozedSlot.self,
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
