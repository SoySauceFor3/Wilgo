import SwiftData
import SwiftUI

struct HabitDetailView: View {
    let habit: Habit

    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingEdit = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statsSection
                    heatmapSection
                }
                .padding()
            }
            .navigationTitle(habit.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { isPresentingEdit = true }
                }
            }
            .sheet(isPresented: $isPresentingEdit) {
                EditHabitView(habit: habit)
            }
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        HStack(spacing: 10) {
            statTile(
                value: "\(habit.checkIns.count)",
                label: "All-time\ncheck-ins"
            )
            statTile(
                value: "\(habit.timesPerDay)×",
                label: "Daily\ngoal"
            )
            statTile(
                value: daysTracked,
                label: "Days\ntracked"
            )
        }
    }

    private var daysTracked: String {
        let days =
            Calendar.current
            .dateComponents([.day], from: habit.createdAt, to: HabitScheduling.now())
            .day ?? 0
        return "\(max(1, days + 1))"
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Heatmap section

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.headline)
            HabitHeatmapView(habit: habit)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Previews

#Preview("Rich history") {
    let container = HeatmapPreviewFactory.richHistoryContainer()
    PreviewWithFirstHabit(container: container) { habit in
        NavigationStack {
            HabitDetailView(habit: habit)
        }
    }
}

#Preview("New habit") {
    let container = HeatmapPreviewFactory.newHabitContainer()
    PreviewWithFirstHabit(container: container) { habit in
        NavigationStack {
            HabitDetailView(habit: habit)
        }
    }
}
