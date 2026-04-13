import SwiftData
import SwiftUI
import UIKit

struct CommitmentStatsCard<TopRightContent: View>: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var commitment: Commitment
    @EnvironmentObject private var checkInUndoManager: CheckInUndoManager
    let slots: [Slot]
    let topRightTitle: String
    var onSnooze: (() -> Void)? = nil
    @ViewBuilder var topRightContent: () -> TopRightContent

    // MARK: - Derived data

    private var psychToday: Date {
        Time.startOfDay(for: Time.now())
    }

    private var checkInsInCurrentTargetCycle: [CheckIn] {
        commitment.checkInsInCycle(
            cycle: commitment.target.cycle, until: psychToday, inclusive: true
        )
    }

    private var targetCycleLabel: String {
        commitment.target.cycle.label(of: psychToday)
    }

    /// Stable random pick — re-sampled only when the commitment identity changes.
    @State private var cachedEncouragement: String? = nil

    // MARK: - Tile helper

    private func statTile<Content: View>(
        title: String,
        background: Color,
        cornerRadius: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !title.isEmpty {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

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
            // Top row: Commitment (1×3) + variant tile (1×2)
            Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                GridRow {
                    statTile(
                        title: "",
                        background: tileBackground,
                        cornerRadius: cornerRadius
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(commitment.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if let encouragement = cachedEncouragement {
                                Text(encouragement)
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                                    .italic()
                                    .lineLimit(1)
                            }
                        }
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
                    // Row A: Completed (1×2) + Snooze (1×2, only when onSnooze provided)
                    GridRow {
                        statTile(
                            title:
                                "\(commitment.target.cycle.kind.nounSingle) \(targetCycleLabel)",
                            background: tileBackground,
                            cornerRadius: cornerRadius
                        ) {
                            HStack(alignment: .bottom, spacing: 4) {
                                Text(
                                    "\(checkInsInCurrentTargetCycle.count)/\(commitment.target.count)"
                                )
                                .font(.title3.bold())
                                .foregroundStyle(.primary)
                                Text("check-ins")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.bottom, 2)
                            }
                        }
                        .frame(height: cellWidth)
                        .gridCellColumns(2)

                        if let onSnooze {
                            Button(action: onSnooze) {
                                Label("Snooze", systemImage: "moon.zzz.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .frame(height: cellWidth)
                            .gridCellColumns(2)
                            .background(
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .fill(Color.indigo)
                            )
                        } else {
                            Color.clear
                                .frame(height: cellWidth)
                                .gridCellColumns(2)
                        }
                    }

                    // Row B: Last 14 days spanning 4 columns
                    GridRow {
                        statTile(
                            title: "Last 14 days",
                            background: tileBackground,
                            cornerRadius: cornerRadius
                        ) {
                            MiniCommitmentHeatmapRow(commitment: commitment, daysToShow: 14)
                        }
                        .frame(height: cellWidth)
                        .gridCellColumns(4)
                    }
                }
                .frame(width: leftBlockWidth, alignment: .leading)

                // Right: Done column (2×1)
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        let checkIn = CheckIn(
                            commitment: commitment
                        )
                        modelContext.insert(checkIn)
                        commitment.checkIns.append(checkIn)  // keep inverse in sync immediately, as inverse relationship propagation takes time.
                        checkInUndoManager.enqueue(
                            checkIn: checkIn, title: "A check-in made for \(commitment.title)"
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                modelContext.delete(checkIn)
                            }
                        }
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
        .onAppear {
            cachedEncouragement = commitment.encouragements.randomElement()
        }
        .onChange(of: commitment.id) {
            cachedEncouragement = commitment.encouragements.randomElement()
        }
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
