import SwiftData
import SwiftUI
import UIKit

struct HabitStatsCard<TopRightContent: View>: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var habit: Habit
    let slots: [Slot]
    let topRightTitle: String
    @ViewBuilder var topRightContent: () -> TopRightContent

    // MARK: - Derived data

    private var psychToday: Date {
        HabitScheduling.psychDay(for: HabitScheduling.now())
    }

    private var skipCreditsUsed: Int {
        SkipCredit.creditsUsedInCycle(for: habit, until: psychToday, inclusive: false)
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
            // Top row: Habit (1×3) + variant tile (1×2)
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
                        title: topRightTitle,
                        background: tileBackground,
                        cornerRadius: cornerRadius
                    ) {
                        topRightContent()
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
                            Text(
                                "\(habit.completedCount(for: psychToday))/\(habit.goalCountPerDay)"
                            )
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
                                Text(habit.cycle.label(of: psychToday))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("\(skipCreditsUsed)/\(habit.skipCreditCount) credits used")
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
                        habit.checkIns.append(checkIn)  // keep inverse in sync immediately, as inverse relationship propagation takes time.
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

