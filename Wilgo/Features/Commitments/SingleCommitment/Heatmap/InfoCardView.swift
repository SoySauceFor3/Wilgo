import Foundation
import SwiftUI

struct CommitmentHeatmapInfoCard: View {
    let period: Heatmap.PeriodData
    let heatmapKind: CycleKind
    let targetKind: CycleKind
    @Binding var selectedPeriod: Heatmap.PeriodData?

    var body: some View {
        let color = Heatmap.cellColor(for: period)
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(period.isBeforeCreation ? 0.7 : 1.0))
                .frame(width: 9, height: 9)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(periodLabel(period))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                if period.isBeforeCreation {
                    Text("Before tracking started")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    // Only show goal/comparison when this heatmap mode matches the
                    // commitment's actual target cycle kind. In other modes the
                    // goal is derived for color scaling only and shouldn't be
                    // surfaced as a "goal" in the UI.
                    if let goal = period.goal, targetKind == heatmapKind {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(period.checkIns.count) / \(goal)")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundStyle(.primary)
                            Text(statusLabel(count: period.checkIns.count, goal: goal))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(
                            "\(period.checkIns.count) check-in\(period.checkIns.count == 1 ? "" : "s")"
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    }

                    if !period.checkIns.isEmpty {
                        Text(
                            period.checkIns.map { $0.createdAt.formatted() }.joined(
                                separator: "  ·  ")
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .onTapGesture { selectedPeriod = nil }
    }

    private func periodLabel(_ period: Heatmap.PeriodData) -> String {
        let fmt = DateFormatter()
        switch heatmapKind {
        case .daily:
            fmt.dateFormat = "EEE, MMM d"
            return fmt.string(from: period.periodStartPsychDay)
        case .weekly:
            fmt.dateFormat = "MMM d"
            let end =
                CommitmentScheduling.calendar.date(
                    byAdding: .day, value: -1, to: period.periodEndPsychDay)
                ?? period.periodEndPsychDay
            return "\(fmt.string(from: period.periodStartPsychDay)) – \(fmt.string(from: end))"
        case .monthly:
            fmt.dateFormat = "MMMM yyyy"
            return fmt.string(from: period.periodStartPsychDay)
        }
    }

    private func statusLabel(count: Int, goal: Int) -> String {
        if count == 0 { return "Missed" }
        if count < goal { return "Partial" }
        if count == goal { return "Goal met ✓" }
        return "+\(count - goal) over goal"
    }
}

// MARK: - Previews

private struct CommitmentHeatmapInfoCardPreviewWrapper: View {
    let heatmapKind: CycleKind
    let period: Heatmap.PeriodData
    @State private var selected: Heatmap.PeriodData?

    init(heatmapKind: CycleKind, period: Heatmap.PeriodData) {
        self.heatmapKind = heatmapKind
        self.period = period
        _selected = State(initialValue: period)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tap card to dismiss (sets selectedPeriod = nil)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            CommitmentHeatmapInfoCard(
                period: selected ?? period,
                heatmapKind: heatmapKind,
                targetKind: .daily,
                selectedPeriod: $selected
            )

            Text("selectedPeriod: \(selected == nil ? "nil" : "set")")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}

private enum CommitmentHeatmapInfoCardPreviewData {
    static var todayStart: Date {
        CommitmentScheduling.calendar.startOfDay(for: .now)
    }

    static var dailyBeforeTracking: Heatmap.PeriodData {
        let start =
            CommitmentScheduling.calendar.date(byAdding: .day, value: -14, to: todayStart)
            ?? todayStart
        let end = CommitmentScheduling.calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return Heatmap.PeriodData(
            id: start,
            periodStartPsychDay: start,
            periodEndPsychDay: end,
            goal: 1,
            checkIns: [],
            isBeforeCreation: true
        )
    }

    static var dailyGoalMissed: Heatmap.PeriodData {
        let start =
            CommitmentScheduling.calendar.date(byAdding: .day, value: -1, to: todayStart)
            ?? todayStart
        let end = CommitmentScheduling.calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return Heatmap.PeriodData(
            id: start,
            periodStartPsychDay: start,
            periodEndPsychDay: end,
            goal: 2,
            checkIns: [],
            isBeforeCreation: false
        )
    }

    static var weeklyNoGoal: Heatmap.PeriodData {
        let start =
            CommitmentScheduling.calendar.date(byAdding: .day, value: -7, to: todayStart)
            ?? todayStart
        let end = CommitmentScheduling.calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return Heatmap.PeriodData(
            id: start,
            periodStartPsychDay: start,
            periodEndPsychDay: end,
            goal: nil,
            checkIns: [],
            isBeforeCreation: false
        )
    }
}

#Preview("Info card — before tracking") {
    CommitmentHeatmapInfoCardPreviewWrapper(
        heatmapKind: .daily,
        period: CommitmentHeatmapInfoCardPreviewData.dailyBeforeTracking
    )
}

#Preview("Info card — goal missed (0/2)") {
    CommitmentHeatmapInfoCardPreviewWrapper(
        heatmapKind: .daily,
        period: CommitmentHeatmapInfoCardPreviewData.dailyGoalMissed
    )
}

#Preview("Info card — no goal (weekly)") {
    CommitmentHeatmapInfoCardPreviewWrapper(
        heatmapKind: .weekly,
        period: CommitmentHeatmapInfoCardPreviewData.weeklyNoGoal
    )
}
