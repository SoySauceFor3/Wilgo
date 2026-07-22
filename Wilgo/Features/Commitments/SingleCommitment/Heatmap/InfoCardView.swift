import Foundation
import SwiftData
import SwiftUI

/// A self-contained info card for a single period (a day, week, or month).
///
/// Given a `commitment` and a date `range`, it derives everything it renders —
/// the live check-in list, the goal, and the "before tracking started" state —
/// so it stays correct after a delete or backfill without any host involvement.
/// It owns its own per-row delete (via `CheckIn.delete`) and its "Add check-in"
/// backfill sheet. Because the check-in list is re-read from the commitment's
/// live SwiftData relationship on every render, deleting a check-in makes its row
/// disappear immediately with no stale-snapshot / tombstone crash.
struct CommitmentHeatmapInfoCard: View {
    let commitment: Commitment
    /// Half-open psych-day range `[lowerBound, upperBound)` this card describes.
    let range: Range<Date>
    /// Period granularity — how to read `range` (day/week/month): drives label and
    /// timestamp formatting and the goal derivation's `periodKind`.
    let rangeKind: CycleKind
    /// Whether to show heatmap-specific chrome — the leading color swatch and the
    /// "N / goal · status" summary line. On in the heatmap (where they're the primary
    /// signal); off in the FCR history section, where the card's header already shows
    /// the count badge + status dot and the swatch/goal line would just duplicate them.
    var showsHeatmapChrome: Bool = true
    /// Called when the user taps the card to dismiss it. Hosts decide what that
    /// means (heatmap clears its selection; FCR passes nil — dismiss is inert there).
    var onDismiss: (() -> Void)?

    @Environment(\.modelContext) private var modelContext

    @State private var pendingDeleteID: UUID? = nil
    @State private var showingBackfill = false

    /// The commitment's own target cycle kind. When it matches `rangeKind`, the
    /// derived goal is the real goal and is surfaced; otherwise the goal is only a
    /// color-scaling artifact and we show a plain check-in count instead.
    private var targetKind: CycleKind { commitment.cycle.kind }

    /// Live check-ins in this period, re-read from the commitment's relationship on
    /// every render (so deletes/backfills reflect immediately). Same helper and
    /// semantics the heatmap grid and FCR builder use, so counts stay consistent.
    private var liveCheckIns: [CheckIn] {
        commitment.checkInsInRange(
            startPsychDay: range.lowerBound, endPsychDay: range.upperBound)
    }

    /// Expected goal for this period, or nil when the commitment has no meaningful target.
    private var goal: Int? {
        Heatmap.expectedGoalPerPeriod(
            target: commitment.target, cycleKind: commitment.cycle.kind, periodKind: rangeKind)
    }

    private var isBeforeCreation: Bool {
        Self.isBeforeCreation(rangeUpperBound: range.upperBound, commitment: commitment)
    }

    /// Whether a period ending at `rangeUpperBound` falls entirely before the
    /// commitment started tracking. Extracted as a static helper so it is unit-testable
    /// without rendering the view.
    static func isBeforeCreation(rangeUpperBound: Date, commitment: Commitment) -> Bool {
        rangeUpperBound <= Time.startOfDay(for: commitment.createdAt)
    }

    /// Whether to render the "N / goal · status" summary line. Only when heatmap chrome
    /// is enabled, a goal exists, and this period's granularity matches the commitment's
    /// target cycle kind (otherwise the goal is only a color-scaling artifact). Static so
    /// it is unit-testable without rendering the view.
    static func shouldShowGoalSummary(
        showsHeatmapChrome: Bool, goal: Int?, targetKind: CycleKind, rangeKind: CycleKind
    ) -> Bool {
        showsHeatmapChrome && goal != nil && targetKind == rangeKind
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if showsHeatmapChrome {
                // Leading color swatch echoing the tapped heatmap cell. Redundant in FCR
                // (the card's header already carries a status dot), so gated off there.
                let color = Heatmap.cellColor(
                    for: Heatmap.PeriodData(
                        id: range.lowerBound,
                        periodStartPsychDay: range.lowerBound,
                        periodEndPsychDay: range.upperBound,
                        goal: goal,
                        checkIns: liveCheckIns,
                        isBeforeCreation: isBeforeCreation
                    ))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(isBeforeCreation ? 0.7 : 1.0))
                    .frame(width: 9, height: 9)
                    .padding(.top, 3)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(periodLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                if isBeforeCreation {
                    Text("Before tracking started")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    // Goal summary is heatmap chrome that duplicates the FCR header, so it's
                    // gated off there. When hidden, fall back to a plain check-in count.
                    if let goal,
                        Self.shouldShowGoalSummary(
                            showsHeatmapChrome: showsHeatmapChrome, goal: goal,
                            targetKind: targetKind, rangeKind: rangeKind)
                    {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(liveCheckIns.count) / \(goal)")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundStyle(.primary)
                            Text(statusLabel(count: liveCheckIns.count, goal: goal))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(
                            "\(liveCheckIns.count) check-in\(liveCheckIns.count == 1 ? "" : "s")"
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    }

                    if !liveCheckIns.isEmpty {
                        ForEach(liveCheckIns, id: \.id) { checkIn in
                            checkInRow(checkIn)
                                .transition(
                                    .opacity.combined(with: .move(edge: .leading)))
                        }
                    }

                    Button {
                        showingBackfill = true
                    } label: {
                        Label("Add check-in", systemImage: "plus.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        // Animate rows in/out as check-ins are added (backfill) or deleted. Keyed on the
        // id list so both insertions and removals trigger the row transitions above.
        .animation(.easeInOut(duration: 0.2), value: liveCheckIns.map(\.id))
        .onTapGesture { onDismiss?() }
        .sheet(isPresented: $showingBackfill) {
            BackfillSheet(
                commitment: commitment,
                dateRange: range.lowerBound...min(range.upperBound.addingTimeInterval(-1), .now)
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func checkInRow(_ checkIn: CheckIn) -> some View {
        let isPending = pendingDeleteID == checkIn.id
        HStack(spacing: 6) {
            Text(checkInTimestamp(checkIn.createdAt))
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
            // Second tap — confirm delete. Reading liveCheckIns on the next render
            // re-derives from the commitment's relationship, so the row disappears
            // with no tombstone access.
            CheckIn.delete(checkIn, from: modelContext)
            pendingDeleteID = nil
        } else {
            // First tap — arm pending state. No timeout; user must tap again to confirm or tap elsewhere to dismiss.
            pendingDeleteID = checkIn.id
        }
    }

    private var periodLabel: String {
        let fmt = DateFormatter()
        switch rangeKind {
        case .daily:
            fmt.dateFormat = "EEE, MMM d"
            return fmt.string(from: range.lowerBound)
        case .weekly:
            fmt.dateFormat = "MMM d"
            let end =
                Time.calendar.date(
                    byAdding: .day, value: -1, to: range.upperBound)
                ?? range.upperBound
            return "\(fmt.string(from: range.lowerBound)) – \(fmt.string(from: end))"
        case .monthly:
            fmt.dateFormat = "MMMM yyyy"
            return fmt.string(from: range.lowerBound)
        }
    }

    private func statusLabel(count: Int, goal: Int) -> String {
        if count == 0 { return "Missed" }
        if count < goal { return "Partial" }
        if count == goal { return "Goal met ✓" }
        return "+\(count - goal) over goal"
    }

    private func checkInTimestamp(_ date: Date) -> String {
        switch rangeKind {
        case .daily:
            return date.formatted(date: .omitted, time: .shortened)
        case .weekly:
            // "Mon, Apr 7, 9:03 AM"
            let fmt = DateFormatter()
            fmt.dateFormat = "EEE, MMM d, h:mm a"
            return fmt.string(from: date)
        case .monthly:
            // "Apr 7, 9:03 AM"
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d, h:mm a"
            return fmt.string(from: date)
        }
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
    let commitment: Commitment
    let range: Range<Date>
    let rangeKind: CycleKind
    var showsHeatmapChrome: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tap card to dismiss (calls onDismiss)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            CommitmentHeatmapInfoCard(
                commitment: commitment,
                range: range,
                rangeKind: rangeKind,
                showsHeatmapChrome: showsHeatmapChrome,
                onDismiss: {}
            )
        }
        .padding()
    }
}

private enum CommitmentHeatmapInfoCardPreviewData {
    static var todayStart: Date {
        Time.calendar.startOfDay(for: .now)
    }

    /// Container + a commitment with three check-ins on `todayStart` (various sources),
    /// for previewing the per-row delete UI and the goal line.
    static func dailyWithCheckInsContainer() -> (ModelContainer, Commitment, Range<Date>) {
        let container = try! ModelContainer(
            for: Commitment.self, Slot.self, CheckIn.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext

        let commitment = Commitment(
            title: "Preview Commitment",
            cycle: Cycle.makeDefault(.daily),
            slots: [],
            target: Target(count: 2)
        )
        ctx.insert(commitment)

        let start = todayStart
        let end = Time.calendar.date(byAdding: .day, value: 1, to: start) ?? start

        for (offset, source) in [
            (9 * 3600 + 3 * 60, CheckInSource.app),  // 9:03 AM
            (11 * 3600 + 45 * 60, CheckInSource.widget),  // 11:45 AM
            (14 * 3600, CheckInSource.liveActivity),  // 2:00 PM
        ] {
            let ci = CheckIn(
                commitment: commitment,
                createdAt: start.addingTimeInterval(TimeInterval(offset)),
                source: source
            )
            ctx.insert(ci)
            commitment.checkIns.append(ci)
        }

        return (container, commitment, start..<end)
    }

    /// Container + a commitment with an empty period one week ago (goal missed).
    static func emptyDailyContainer() -> (ModelContainer, Commitment, Range<Date>) {
        let container = try! ModelContainer(
            for: Commitment.self, Slot.self, CheckIn.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let commitment = Commitment(
            title: "Preview Commitment",
            cycle: Cycle.makeDefault(.daily),
            slots: [],
            target: Target(count: 2)
        )
        ctx.insert(commitment)

        let start = Time.calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let end = Time.calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return (container, commitment, start..<end)
    }
}

#Preview("Info card — with check-ins (delete UI)") {
    let (container, commitment, range) =
        CommitmentHeatmapInfoCardPreviewData.dailyWithCheckInsContainer()
    CommitmentHeatmapInfoCardPreviewWrapper(
        commitment: commitment,
        range: range,
        rangeKind: .daily
    )
    .modelContainer(container)
}

#Preview("Info card — goal missed (0/2)") {
    let (container, commitment, range) =
        CommitmentHeatmapInfoCardPreviewData.emptyDailyContainer()
    CommitmentHeatmapInfoCardPreviewWrapper(
        commitment: commitment,
        range: range,
        rangeKind: .daily
    )
    .modelContainer(container)
}

#Preview("Info card — FCR (no chrome: no swatch/goal line)") {
    let (container, commitment, range) =
        CommitmentHeatmapInfoCardPreviewData.dailyWithCheckInsContainer()
    CommitmentHeatmapInfoCardPreviewWrapper(
        commitment: commitment,
        range: range,
        rangeKind: .daily,
        showsHeatmapChrome: false
    )
    .modelContainer(container)
}
