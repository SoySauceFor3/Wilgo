import SwiftData
import SwiftUI

struct ListHabitView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.createdAt, order: .forward) private var habits: [Habit]
    @State private var isPresentingAddHabit: Bool = false
    @State private var habitForDetail: Habit?

    var body: some View {
        NavigationStack {
            List {
                ForEach(habits) { habit in
                    HabitRowView(habit: habit)
                        .contentShape(Rectangle())
                        .onTapGesture { habitForDetail = habit }
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
            .sheet(item: $habitForDetail) { habit in
                HabitDetailView(habit: habit)
                    .presentationDetents([.fraction(0.65), .large])
                    .presentationDragIndicator(.visible)
            }
        }
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

                Text("\(habit.goalCountPerDay)× daily")
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

                    Text("\(habit.skipCreditCount) / \(habit.cycle.label)")
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
        return habit.slots.map { "\(formattedTime(from: $0.start))–\(formattedTime(from: $0.end))" }
            .joined(separator: ", ")
    }
}

private func makePreviewContainerWithSamples() throws -> ModelContainer {
    let container = try ModelContainer(
        for: Habit.self, Slot.self, HabitCheckIn.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = container.mainContext
    let calendar = Calendar.current

    func slot(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int) -> Slot {
        Slot(
            start: calendar.date(from: DateComponents(hour: h1, minute: m1)) ?? Date(),
            end: calendar.date(from: DateComponents(hour: h2, minute: m2)) ?? Date()
        )
    }

    let samples: [Habit] = [
        Habit(
            title: "Workout", slots: [slot(6, 0, 8, 0), slot(8, 0, 10, 0)], skipCreditCount: 5,
            cycle: .monthly(day: 1), proofOfWorkType: .manual, goalCountPerDay: 1),
        Habit(
            title: "Read 30 mins 📚", slots: [slot(9, 0, 11, 0)], skipCreditCount: 1, cycle: .daily,
            proofOfWorkType: .manual, goalCountPerDay: 1),
        Habit(
            title: "Drink 2L Water 💧", slots: [slot(12, 0, 14, 0)], skipCreditCount: 1,
            cycle: .daily, proofOfWorkType: .manual, goalCountPerDay: 1),
        Habit(
            title: "Meditate 10 mins 🧘", slots: [slot(15, 0, 17, 0)], skipCreditCount: 1,
            cycle: .daily, proofOfWorkType: .manual, goalCountPerDay: 1),
        Habit(
            title: "No social media after 9 PM 📵", slots: [slot(21, 0, 23, 0)], skipCreditCount: 1,
            cycle: .daily, proofOfWorkType: .manual, goalCountPerDay: 1),
    ]
    for habit in samples {
        ctx.insert(habit)
    }
    return container
}

struct ListHabitView_Previews: PreviewProvider {
    static var previews: some View {
        ListHabitView()
            .modelContainer(try! makePreviewContainerWithSamples())
    }
}
