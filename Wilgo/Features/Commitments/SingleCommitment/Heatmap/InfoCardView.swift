import Foundation
import SwiftData
import SwiftUI

struct CommitmentHeatmapInfoCard: View {
    let period: Heatmap.PeriodData
    let heatmapKind: CycleKind
    let targetKind: CycleKind
    @Binding var selectedPeriod: Heatmap.PeriodData?
    var onDelete: (CheckIn) -> Void = { _ in }
    var onAddCheckIn: (() -> Void)? = nil

    @State private var pendingDeleteID: UUID? = nil

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
                        let sorted = period.checkIns.sorted { $0.createdAt < $1.createdAt }
                        ForEach(sorted, id: \.id) { checkIn in
                            checkInRow(checkIn)
                        }
                    }

                    if let onAddCheckIn {
                        Button {
                            onAddCheckIn()
                        } label: {
                            Label("Add check-in", systemImage: "plus.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
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

    @ViewBuilder
    private func checkInRow(_ checkIn: CheckIn) -> some View {
        let isPending = pendingDeleteID == checkIn.id
        HStack(spacing: 6) {
            Text(checkIn.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if let label = sourceLabel(for: checkIn.source) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                handleDeleteTap(checkIn)
            } label: {
                if isPending {
                    Text("Confirm")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red)
                } else {
                    Text("−")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isPending
                ? Color.red.opacity(0.15)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func handleDeleteTap(_ checkIn: CheckIn) {
        if pendingDeleteID == checkIn.id {
            // Second tap within 1s — confirm delete
            onDelete(checkIn)
            pendingDeleteID = nil
        } else {
            // First tap — arm pending state. Capture only the Sendable UUID,
            // not the non-Sendable CheckIn model object, to satisfy Swift 6 concurrency.
            let capturedID = checkIn.id
            pendingDeleteID = capturedID
            Task {
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run {
                    if pendingDeleteID == capturedID {
                        pendingDeleteID = nil
                    }
                }
            }
        }
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
                Time.calendar.date(
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

    private func sourceLabel(for source: CheckInSource) -> String? {
        switch source {
        case .app: return nil
        case .widget: return "widget"
        case .liveActivity: return "lock screen"
        case .backfill: return "backfilled"
        }
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
                selectedPeriod: $selected,
                onDelete: { _ in }
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
        Time.calendar.startOfDay(for: .now)
    }

    static var dailyBeforeTracking: Heatmap.PeriodData {
        let start =
            Time.calendar.date(byAdding: .day, value: -14, to: todayStart)
            ?? todayStart
        let end = Time.calendar.date(byAdding: .day, value: 1, to: start) ?? start
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
            Time.calendar.date(byAdding: .day, value: -1, to: todayStart)
            ?? todayStart
        let end = Time.calendar.date(byAdding: .day, value: 1, to: start) ?? start
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
            Time.calendar.date(byAdding: .day, value: -7, to: todayStart)
            ?? todayStart
        let end = Time.calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return Heatmap.PeriodData(
            id: start,
            periodStartPsychDay: start,
            periodEndPsychDay: end,
            goal: nil,
            checkIns: [],
            isBeforeCreation: false
        )
    }

    /// Container + period for previewing the per-row delete UI (check-ins with various sources).
    static func dailyWithCheckInsContainer() -> (ModelContainer, Heatmap.PeriodData) {
        let container = try! ModelContainer(
            for: Commitment.self, Slot.self, CheckIn.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext

        let commitment = Commitment(
            title: "Preview Commitment",
            slots: [],
            target: Target(cycle: Cycle.anchored(.daily, at: .now), count: 2)
        )
        ctx.insert(commitment)

        let start = todayStart
        let end = Time.calendar.date(byAdding: .day, value: 1, to: start) ?? start

        let ci1 = CheckIn(
            commitment: commitment,
            createdAt: start.addingTimeInterval(9 * 3600 + 3 * 60),  // 9:03 AM
            source: .app
        )
        ctx.insert(ci1)
        commitment.checkIns.append(ci1)

        let ci2 = CheckIn(
            commitment: commitment,
            createdAt: start.addingTimeInterval(11 * 3600 + 45 * 60),  // 11:45 AM
            source: .widget
        )
        ctx.insert(ci2)
        commitment.checkIns.append(ci2)

        let ci3 = CheckIn(
            commitment: commitment,
            createdAt: start.addingTimeInterval(14 * 3600),  // 2:00 PM
            source: .liveActivity
        )
        ctx.insert(ci3)
        commitment.checkIns.append(ci3)

        let period = Heatmap.PeriodData(
            id: start,
            periodStartPsychDay: start,
            periodEndPsychDay: end,
            goal: 2,
            checkIns: [ci1, ci2, ci3],
            isBeforeCreation: false
        )

        return (container, period)
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

#Preview("Info card — with check-ins (delete UI)") {
    let (container, period) = CommitmentHeatmapInfoCardPreviewData.dailyWithCheckInsContainer()
    CommitmentHeatmapInfoCardPreviewWrapper(
        heatmapKind: .daily,
        period: period
    )
    .modelContainer(container)
}
