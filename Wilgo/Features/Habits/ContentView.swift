//
//  ContentView.swift
//  Wilgo
//
//  Created by Xinya Yang on 2/24/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.createdAt, order: .forward) private var habits: [Habit]
    @State private var isPresentingAddHabit: Bool = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(habits) { habit in
                    HabitRowView(habit: habit)
                }
                .onDelete(perform: deleteHabits)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Habits")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isPresentingAddHabit = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .sheet(isPresented: $isPresentingAddHabit) {
                AddHabitView()
            }
        }
    }

    /// Formats a `Date` that represents a time-of-day into a short string like "6:00 AM".
    private func formattedTime(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func deleteHabits(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(habits[index])
            }
        }
    }
}

private struct HabitRowView: View {
    @Bindable var habit: Habit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top line: status + title
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(habit.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()
            }

            // Second line: frequency / schedule
            HStack(spacing: 4) {
                Label("Schedule", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(habit.frequencyCount)× \(habit.frequencyPeriod.rawValue.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Third line: golden window
            HStack(spacing: 4) {
                Label("Window", systemImage: "sun.max")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(formattedTime(from: habit.idealWindowStart)) – \(formattedTime(from: habit.idealWindowEnd))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Fourth line: skip credits + proof-of-work
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Label("Skip", systemImage: "arrow.uturn.left")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(habit.skipCreditCount) / \(habit.skipCreditPeriod.rawValue.lowercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(habit.proofOfWorkType.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.1))
                    )
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func formattedTime(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

#Preview {
    let container = try! ModelContainer(for: Habit.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let ctx = container.mainContext

    let calendar = Calendar.current

    let samples: [Habit] = [
        Habit(
            title: "Workout",
            frequencyCount: 1,
            frequencyPeriod: .daily,
            idealWindowStart: calendar.date(from: DateComponents(hour: 6, minute: 0)) ?? Date(),
            idealWindowEnd: calendar.date(from: DateComponents(hour: 8, minute: 0)) ?? Date(),
            skipCreditCount: 5,
            skipCreditPeriod: .monthly,
            proofOfWorkType: .manual
        ),
        Habit(
            title: "Read 30 mins 📚",
            frequencyCount: 1,
            frequencyPeriod: .daily,
            idealWindowStart: calendar.date(from: DateComponents(hour: 9, minute: 0)) ?? Date(),
            idealWindowEnd: calendar.date(from: DateComponents(hour: 11, minute: 0)) ?? Date(),
            skipCreditCount: 1,
            skipCreditPeriod: .daily,
            proofOfWorkType: .manual
        ),
        Habit(
            title: "Drink 2L Water 💧",
            frequencyCount: 1,
            frequencyPeriod: .daily,
            idealWindowStart: calendar.date(from: DateComponents(hour: 12, minute: 0)) ?? Date(),
            idealWindowEnd: calendar.date(from: DateComponents(hour: 14, minute: 0)) ?? Date(),
            skipCreditCount: 1,
            skipCreditPeriod: .daily,
            proofOfWorkType: .manual
        ),
        Habit(
            title: "Meditate 10 mins 🧘",
            frequencyCount: 1,
            frequencyPeriod: .daily,
            idealWindowStart: calendar.date(from: DateComponents(hour: 15, minute: 0)) ?? Date(),
            idealWindowEnd: calendar.date(from: DateComponents(hour: 17, minute: 0)) ?? Date(),
            skipCreditCount: 1,
            skipCreditPeriod: .daily,
            proofOfWorkType: .manual
        ),
        Habit(
            title: "No social media after 9 PM 📵",
            frequencyCount: 1,
            frequencyPeriod: .daily,
            idealWindowStart: calendar.date(from: DateComponents(hour: 21, minute: 0)) ?? Date(),
            idealWindowEnd: calendar.date(from: DateComponents(hour: 23, minute: 0)) ?? Date(),
            skipCreditCount: 1,
            skipCreditPeriod: .daily,
            proofOfWorkType: .manual
        ),
    ]

    for habit in samples {
        ctx.insert(habit)
    }

    return ContentView()
        .modelContainer(container)
}
