import SwiftData
import SwiftUI
import UIKit

struct CurrentHabitRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var habit: Habit
    let slots: [Slot]

    // MARK: - Derived data

    private var psychToday: Date {
        HabitScheduling.psychDay(for: HabitScheduling.now())
    }

    private var skipCreditsUsed: Int {
        SkipCredit.creditsUsedInCycle(
            for: habit,
            until: Calendar.current.date(byAdding: .day, value: -1, to: psychToday) ?? psychToday)
    }

    private var skipCreditsAllowance: Int {
        habit.skipCreditCount
    }

    private var skipCycleLabel: String {
        habit.cycle.label(of: psychToday)
    }

    private var completedToday: Int {
        habit.completedCount(for: psychToday)
    }

    private var todayGoal: Int {
        max(1, habit.goalCountPerDay)
    }

    // MARK: - Tile helper

    private func statTile<Content: View>(
        title: String,
        background: Color,
        cornerRadius: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    var body: some View {
        let cornerRadius: CGFloat = 14
        let tileBackground = Color(.secondarySystemBackground)
        let gap: CGFloat = 10
        let columns: CGFloat = 5  // full grid width: 5 columns
        let totalWidth = DisplayInfo.width - 32  // account for outer padding
        // totalWidth = columns * cellWidth + (columns - 1) * gap
        let cellWidth = (totalWidth - (columns - 1) * gap) / columns
        let leftBlockColumns: CGFloat = 4
        let leftBlockWidth = leftBlockColumns * cellWidth + (leftBlockColumns - 1) * gap

        VStack(spacing: gap) {
            // Top row: Habit (1×3) + Window (1×2)
            Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                GridRow {
                    statTile(
                        title: "Habit",
                        background: tileBackground,
                        cornerRadius: cornerRadius
                    ) {
                        Text(habit.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    .frame(height: cellWidth)
                    .gridCellColumns(3)

                    statTile(
                        title: "Window",
                        background: tileBackground,
                        cornerRadius: cornerRadius
                    ) {
                        Text(slots.map { $0.slotTimeText }.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.primary)
                    }
                    .frame(height: cellWidth)
                    .gridCellColumns(2)
                }
            }
            .frame(width: totalWidth, alignment: .leading)

            // Bottom block: 2 × 5 (left 2×4 stats, right 2×1 Done)
            HStack(alignment: .top, spacing: gap) {
                // Left: 2×4 stats area
                Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                    // Row A: Completed (1×2) + Skip credits (1×2)
                    GridRow {
                        statTile(
                            title: "Completed today",
                            background: tileBackground,
                            cornerRadius: cornerRadius
                        ) {
                            Text("\(completedToday)/\(todayGoal)")
                                .font(.title3.bold())
                                .foregroundStyle(.primary)
                        }
                        .frame(height: cellWidth)
                        .gridCellColumns(2)

                        statTile(
                            title: "Skip credits",
                            background: tileBackground,
                            cornerRadius: cornerRadius
                        ) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skipCycleLabel)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("\(skipCreditsUsed)/\(skipCreditsAllowance) credits used")
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .frame(height: cellWidth)
                        .gridCellColumns(2)
                    }

                    // Row B: Last 14 days spanning 4 columns
                    GridRow {
                        statTile(
                            title: "Last 14 days",
                            background: tileBackground,
                            cornerRadius: cornerRadius
                        ) {
                            MiniHabitHeatmapRow(habit: habit, daysToShow: 14)
                        }
                        .frame(height: cellWidth)
                        .gridCellColumns(4)
                    }
                }
                .frame(width: leftBlockWidth, alignment: .leading)

                // Right: Done column (2×1)
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        let checkIn = HabitCheckIn(
                            habit: habit
                        )
                        modelContext.insert(checkIn)
                        habit.checkIns.append(checkIn)  // keep inverse in sync immediately, as inverse relationship propogation takes time.
                    }
                } label: {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .frame(width: cellWidth, height: cellWidth * 2 + gap)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.green)
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
        )
    }
}

#Preview {
    let calendar = Calendar.current
    let today = Date()
    let start = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: today) ?? today
    let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: today) ?? today

    let slot = Slot(start: start, end: end)
    let habit = Habit(
        title: "Morning reading",
        slots: [slot],
        skipCreditCount: 3,
        cycle: .weekly(weekday: 2),
        goalCountPerDay: 1
    )

    CurrentHabitRow(habit: habit, slots: [slot])
        .modelContainer(
            for: [Habit.self, Slot.self, HabitCheckIn.self], inMemory: true
        )
        .padding()
}

private struct DisplayInfo {
    private static var windowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
    }

    private static var screenBounds: CGRect {
        windowScene?.screen.bounds ?? .zero
    }

    static var width: CGFloat {
        screenBounds.width
    }
}

