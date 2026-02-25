//
//  StageView.swift
//  Wilgo
//
//  Page 1: The Stage — dynamic dashboard highlighting the in-window habit with phase-based styling.
//

import SwiftUI
import SwiftData

struct StageView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.createdAt, order: .forward) private var habits: [Habit]

    /// Primary habit to feature: in gentle, judgmental, or critical phase; earliest soft deadline first.
    private var primaryHabit: Habit? {
        let now = Date()
        let active = habits.filter { habit in
            let phase = PhaseEngine.phase(for: habit, now: now)
            return phase == .gentle || phase == .judgmental || phase == .critical
        }
        return active.min(by: { HabitScheduling.softDeadline(for: $0, now: now) < HabitScheduling.softDeadline(for: $1, now: now) })
    }

    /// Upcoming habits (window start still later today), sorted by window start.
    private var upcomingHabits: [Habit] {
        let now = Date()
        return habits
            .filter { HabitScheduling.isUpcomingToday($0, now: now) }
            .sorted { HabitScheduling.windowStartToday(for: $0) < HabitScheduling.windowStartToday(for: $1) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let habit = primaryHabit {
                        PrimaryHabitCard(habit: habit)
                    } else {
                        EmptyStageCard()
                    }

                    if !upcomingHabits.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Upcoming today")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(upcomingHabits) { habit in
                                UpcomingHabitRow(habit: habit)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stage")
        }
    }
}

// MARK: - Primary card (in-window habit)

private struct PrimaryHabitCard: View {
    @Bindable var habit: Habit

    var body: some View {
        let (_, style) = PhaseEngine.phaseAndStyle(for: habit)

        VStack(alignment: .leading, spacing: 20) {
            // Mascot area placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(style.color.opacity(0.15))
                .frame(height: 80)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.system(size: 36))
                        .foregroundStyle(style.color)
                }

            VStack(alignment: .leading, spacing: 8) {
                Text(habit.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(style.toneMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        habit.isCompleted = true
                    }
                } label: {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(habit.isCompleted)

                Button {
                    burnCredit()
                } label: {
                    Label("Burn credit", systemImage: "flame")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .tint(style.color)
                .disabled(habit.skipCreditCount <= 0)
            }

            HStack {
                Text("Skip credits:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(habit.skipCreditCount) left")
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(style.color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(style.color.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func burnCredit() {
        withAnimation {
            if habit.skipCreditCount > 0 {
                habit.skipCreditCount -= 1
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
            Text("No habit in window right now")
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

// MARK: - Upcoming row

private struct UpcomingHabitRow: View {
    let habit: Habit

    private func formattedTime(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(formattedTime(from: habit.idealWindowStart)) – \(formattedTime(from: habit.idealWindowEnd))")
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

// MARK: - Previews

#Preview("Stage with multiple habits") {
    let container = try! ModelContainer(for: Habit.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let ctx = container.mainContext
    let calendar = Calendar.current

    let habit1 = Habit(
        title: "habit 1",
        frequencyCount: 1,
        frequencyPeriod: .daily,
        idealWindowStart: calendar.date(from: DateComponents(hour: 0, minute: 0)) ?? Date(),
        idealWindowEnd: calendar.date(from: DateComponents(hour: 10, minute: 0)) ?? Date(),
        skipCreditCount: 5,
        skipCreditPeriod: .monthly,
        proofOfWorkType: .manual
    )
    let habit2 = Habit(
        title: "habit 2",
        frequencyCount: 1,
        frequencyPeriod: .daily,
        idealWindowStart: calendar.date(from: DateComponents(hour: 3, minute: 0)) ?? Date(),
        idealWindowEnd: calendar.date(from: DateComponents(hour: 4, minute: 30)) ?? Date(),
        skipCreditCount: 3,
        skipCreditPeriod: .weekly,
        proofOfWorkType: .manual
    )
    let habit3 = Habit(
        title: "habit 3",
        frequencyCount: 1,
        frequencyPeriod: .daily,
        idealWindowStart: calendar.date(from: DateComponents(hour: 4, minute: 0)) ?? Date(),
        idealWindowEnd: calendar.date(from: DateComponents(hour: 5, minute: 30)) ?? Date(),
        skipCreditCount: 2,
        skipCreditPeriod: .weekly,
        proofOfWorkType: .manual
    )

    ctx.insert(habit1)
    ctx.insert(habit2)
    ctx.insert(habit3)

    return StageView()
        .modelContainer(container)
}


#Preview("Stage with 1 habit") {
    let container = try! ModelContainer(for: Habit.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let ctx = container.mainContext
    let calendar = Calendar.current
    let habit = Habit(
        title: "Workout",
        frequencyCount: 1,
        frequencyPeriod: .daily,
        idealWindowStart: calendar.date(from: DateComponents(hour: 0, minute: 0)) ?? Date(),
        idealWindowEnd: calendar.date(from: DateComponents(hour: 0, minute: 10)) ?? Date(),
        skipCreditCount: 5,
        skipCreditPeriod: .monthly,
        proofOfWorkType: .manual
    )
    ctx.insert(habit)
    return StageView()
        .modelContainer(container)
}

#Preview("Stage empty") {
    StageView()
        .modelContainer(try! ModelContainer(for: Habit.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
}
