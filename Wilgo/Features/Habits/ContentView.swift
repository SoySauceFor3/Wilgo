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

            // Second line: schedule (N× daily)
            HStack(spacing: 4) {
                Label("Schedule", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(habit.timesPerDay)× daily")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Third line: ideal windows (one per slot)
            HStack(spacing: 4) {
                Label("Windows", systemImage: "sun.max")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(slotWindowsSummary(habit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Fourth line: skip credits + proof-of-work
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Label("Skip", systemImage: "arrow.uturn.left")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(habit.skipCreditCount) / \(habit.skipCreditPeriod.rawValue)")
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

    private func slotWindowsSummary(_ habit: Habit) -> String {
        return habit.slots.map { "\(formattedTime(from: $0.start))–\(formattedTime(from: $0.end))" }.joined(separator: ", ")
    }
}

private func makePreviewContainerWithSamples() throws -> ModelContainer {
    let container = try ModelContainer(
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

    let samples: [Habit] = [
        Habit(title: "Workout", slots: [slot(6, 0, 8, 0), slot(8, 0, 10, 0)], skipCreditCount: 5, skipCreditPeriod: .monthly, proofOfWorkType: .manual),
        Habit(title: "Read 30 mins 📚", slots: [slot(9, 0, 11, 0)], skipCreditCount: 1, skipCreditPeriod: .daily, proofOfWorkType: .manual),
        Habit(title: "Drink 2L Water 💧", slots: [slot(12, 0, 14, 0)], skipCreditCount: 1, skipCreditPeriod: .daily, proofOfWorkType: .manual),
        Habit(title: "Meditate 10 mins 🧘", slots: [slot(15, 0, 17, 0)], skipCreditCount: 1, skipCreditPeriod: .daily, proofOfWorkType: .manual),
        Habit(title: "No social media after 9 PM 📵", slots: [slot(21, 0, 23, 0)], skipCreditCount: 1, skipCreditPeriod: .daily, proofOfWorkType: .manual),
    ]
    for habit in samples {
        ctx.insert(habit)
    }
    return container
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .modelContainer(try! makePreviewContainerWithSamples())
    }
}
