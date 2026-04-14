import SwiftData
import SwiftUI
import WidgetKit

// Shared heatmap layout constants so smaller views (e.g. stage row) stay aligned.
private let cellSize: CGFloat = 11
private let cellSpacing: CGFloat = 3

/// Larger cell size for weekly/monthly modes to avoid overlapping date labels.
private let cellSizeWide: CGFloat = 22

/// Height of the monthly heatmap content (label row + cell + vertical padding) so the view occupies space.
private let monthlyHeatmapContentHeight: CGFloat =
    18 + cellSpacing + cellSizeWide + 4 * 2

/// Columns in weekly grid (4 rows × 7 columns = 28 slots, we use 26).
private let weeklyGridColumns = 7
private let weeklyGridRows = 4

// MARK: - Legend (shared)

struct CommitmentHeatmapLegendView: View {
    let commitment: Commitment
    let heatmapKind: CycleKind

    private struct LegendSample: Identifiable {
        let id = UUID()
        let progress: Double  // 0...1
        let label: String
        let value: Int
    }

    private var expectedGoal: Int? {
        Heatmap.expectedGoalPerPeriod(target: commitment.target, periodKind: heatmapKind)
    }

    private var samples: [LegendSample] {
        guard let goal = expectedGoal, goal > 0 else {
            // Fallback absolute scale when we don't have a meaningful goal.
            let rawValues: [Int] = [0, 1, 2, 3, 4, 5]
            let uniqueValues = Array(Set(rawValues)).sorted()
            return uniqueValues.map { value in
                let progress = min(Double(value) / 4.0, 1.0)
                return LegendSample(progress: progress, label: "\(value)", value: value)
            }
        }

        // Candidate counts anchored around the goal; we will uniquify them.
        let rawValues: [Int] = [
            0,
            max(1, Int(round(0.25 * Double(goal)))),
            max(1, Int(round(0.5 * Double(goal)))),
            goal,
            Int(round(1.5 * Double(goal))),
            2 * goal,
        ]

        let uniqueValues = Array(Set(rawValues)).sorted()

        return uniqueValues.enumerated().map { index, value in
            // Map counts to intensity such that:
            // count == goal   → 0.5 intensity
            // count >= 2*goal → 1.0 intensity
            let scaled = min(Double(value) / Double(2 * goal), 1.0)
            let isMaxBucket = index == uniqueValues.count - 1
            let label = isMaxBucket ? "\(value)+" : "\(value)"
            return LegendSample(progress: scaled, label: label, value: value)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            legendItem(Color(.systemGray5), "Today", borderColor: Color.primary.opacity(0.45))
            legendItem(Color(.systemGray3), "N/A")
            ForEach(samples) { sample in
                let isTargetBucket =
                    (commitment.target.cycle.kind == heatmapKind)
                    && (expectedGoal != nil && sample.value == expectedGoal)
                legendItem(
                    heatmapLegendColorSample(progress: sample.progress),
                    sample.label,
                    isTarget: isTargetBucket
                )
            }
        }
    }

    private func legendItem(
        _ color: Color,
        _ label: String,
        borderColor: Color? = nil,
        isTarget: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: cellSize, height: cellSize)
                .overlay {
                    if let bc = borderColor {
                        RoundedRectangle(cornerRadius: 2).stroke(bc, lineWidth: 1.5)
                    }
                }
            Text(label)
                .font(.system(size: 9, weight: isTarget ? .semibold : .regular))
                .underline(isTarget)
                .foregroundStyle(isTarget ? .primary : .secondary)
        }
    }

    private func heatmapLegendColorSample(progress: Double) -> Color {
        Heatmap.baseColor(forProgress: progress)
    }
}

extension Heatmap {
    // Base color mapping shared by the heatmap cells and legend.
    static func baseColor(forProgress rawProgress: Double) -> Color {
        let progress = max(0.0, min(rawProgress, 1.0))

        if progress == 0 {
            return .white
        }

        // Green hue, with stronger contrast at high progress.
        let saturation = 0.3 + 0.7 * progress
        let brightness = 1.0 - 0.7 * progress

        return Color(
            hue: 0.37,
            saturation: saturation,
            brightness: brightness
        )
    }

    static func cellColor(for period: PeriodData) -> Color {
        if period.isFuture { return .clear }
        if period.isBeforeCreation { return Color(.systemGray3) }

        let count = period.checkIns.count
        if count == 0 {
            return .white
        }

        if let goal = period.goal, goal > 0 {
            // Map counts to intensity such that:
            // count == goal   → 0.5 intensity
            // count >= 2*goal → 1.0 intensity
            let progress = min(Double(count) / Double(2 * goal), 1.0)
            return baseColor(forProgress: progress)
        }

        // Fallback for periods without a goal: simple linear scaling based on count.
        let fallbackIntensity = min(Double(count) / 4.0, 1.0)
        return baseColor(forProgress: fallbackIntensity)
    }
}

// MARK: - View

struct CommitmentHeatmapView: View {
    let commitment: Commitment

    @Environment(\.modelContext) private var modelContext

    @State private var heatmapKind: CycleKind = .daily
    @State private var selectedPeriod: Heatmap.PeriodData? = nil
    @State private var backfillPeriod: Heatmap.PeriodData? = nil
    private var context: Heatmap.Context { Heatmap.Context(commitment: commitment) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            heatmapKindPicker

            heatmapContent

            CommitmentHeatmapLegendView(commitment: commitment, heatmapKind: heatmapKind)

            if let selected = selectedPeriod {
                CommitmentHeatmapInfoCard(
                    period: selected,
                    heatmapKind: heatmapKind,
                    targetKind: context.target.kind,
                    selectedPeriod: $selectedPeriod,
                    onDelete: { checkIn in
                        modelContext.delete(checkIn)
                        // Dismiss the info card immediately — its PeriodData still holds
                        // a reference to the now-deleted CheckIn, and accessing any property
                        // on a SwiftData tombstone crashes.
                        selectedPeriod = nil
                        WidgetCenter.shared.reloadTimelines(
                            ofKind: WilgoConstants.currentCommitmentWidgetKind)
                    },
                    onAddCheckIn: { backfillPeriod = selectedPeriod }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(duration: 0.22), value: selectedPeriod?.id)
        .animation(.spring(duration: 0.22), value: heatmapKind)
        .sheet(item: $backfillPeriod) { period in
            BackfillSheet(
                commitment: commitment,
                dateRange: period.periodStartPsychDay...min(
                    period.periodEndPsychDay.addingTimeInterval(-1), Date.now)
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var heatmapKindPicker: some View {
        Picker("View", selection: $heatmapKind) {
            ForEach(CycleKind.allCases, id: \.self) { kind in
                Text(kind.adj).tag(kind)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var heatmapContent: some View {
        switch heatmapKind {
        case .daily:
            dailyHeatmapGrid
        case .weekly:
            weeklyHeatmapGrid
        case .monthly:
            monthlyHeatmapCentered
        }
    }

    /// Shared helper for simple "header row + N rows of cells" heatmap layouts.
    /// Callers provide how to render each header column and each cell.
    private func headerGrid<Header: View, Cell: View>(
        columns: Int,
        rows: Int,
        @ViewBuilder header: @escaping (Int) -> Header,
        @ViewBuilder cell: @escaping (Int, Int) -> Cell
    ) -> some View {
        Grid(
            alignment: .topLeading,
            horizontalSpacing: cellSpacing,
            verticalSpacing: cellSpacing
        ) {
            // Top header row.
            GridRow {
                ForEach(0..<columns, id: \.self) { col in
                    header(col)
                }
            }

            // Subsequent rows of cells.
            ForEach(0..<rows, id: \.self) { row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { col in
                        cell(col, row)
                    }
                }
            }
        }
    }

    // MARK: Daily grid (7 rows × x columns) – pinned weekday column + scrollable Grid

    private static let dailyDowLabels: [String] = ["M", "T", "W", "T", "F", "S", "S"]
    private static let dailyLabelRowHeight: CGFloat = 14

    private var dailyHeatmapGrid: some View {
        let periods = Heatmap.DailyDataBuilder(context: context).dailyPeriods()
        let columns = Self.buildDailyColumns(from: periods)
        let monthLabelsByColumn = Self.buildMonthLabelsByColumn(from: columns)

        return HStack(alignment: .top, spacing: cellSpacing) {
            // Pinned left column: header cell + weekday labels (no horizontal scroll).
            dailyPinnedLeftColumn()

            ScrollView(.horizontal, showsIndicators: false) {
                dailyScrollableGrid(columns: columns, monthLabelsByColumn: monthLabelsByColumn)
                    .padding(.trailing, 4)
            }
            .defaultScrollAnchor(.trailing)
        }
        .padding(.vertical, 4)
    }

    /// Pinned left column: one header row (height matches month label row) + 7 weekday labels.
    private func dailyPinnedLeftColumn() -> some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: cellSpacing) {
            GridRow {
                Color.clear.frame(width: cellSize, height: Self.dailyLabelRowHeight)
            }
            ForEach(0..<7, id: \.self) { dayIdx in
                GridRow {
                    Text(Self.dailyDowLabels[dayIdx])
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: cellSize, height: cellSize)
                }
            }
        }
    }

    /// Scrollable grid: one row of month labels (or empty) + 7 rows of period cells; aligns with pinned column by using same row heights.
    private func dailyScrollableGrid(
        columns: [[Heatmap.PeriodData?]],
        monthLabelsByColumn: [Int: String]
    ) -> some View {
        headerGrid(
            columns: columns.count,
            rows: 7,
            header: { weekIdx in
                if let label = monthLabelsByColumn[weekIdx] {
                    Text(label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .frame(width: cellSize, height: Self.dailyLabelRowHeight)
                } else {
                    Color.clear.frame(width: cellSize, height: Self.dailyLabelRowHeight)
                }
            },
            cell: { weekIdx, dayIdx in
                if let period = columns[weekIdx][dayIdx] {
                    periodCell(period)
                } else {
                    Color.clear.frame(width: cellSize, height: cellSize)
                }
            }
        )
    }

    private var weeklyHeatmapGrid: some View {
        let periods = Heatmap.WeeklyDataBuilder(context: context).weeklyPeriods()
        let cellSize = cellSizeWide
        let grid = headerGrid(
            columns: weeklyGridColumns,
            rows: weeklyGridRows,
            header: { col in
                let periodIdxForLabel = col * weeklyGridRows
                if periodIdxForLabel < periods.count {
                    Text(Self.periodColumnLabel(periods[periodIdxForLabel], kind: .weekly))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.center)
                        .frame(width: cellSize, height: 18)
                } else {
                    Color.clear.frame(width: cellSize, height: 18)
                }
            },
            cell: { col, row in
                let periodIdx = col * weeklyGridRows + row
                if periodIdx < periods.count {
                    periodCell(periods[periodIdx], cellSize: cellSize)
                } else {
                    Color.clear.frame(width: cellSize, height: cellSize)
                }
            }
        )

        return HStack {
            Spacer(minLength: 0)
            grid
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var monthlyHeatmapCentered: some View {
        let periods = Heatmap.MonthlyDataBuilder(context: context).monthlyPeriods()
        let cellSize = cellSizeWide
        let grid = headerGrid(
            columns: periods.count,
            rows: 1,
            header: { col in
                let period = periods[col]
                Text(Self.periodColumnLabel(period, kind: .monthly))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: cellSize, height: 18, alignment: .center)
            },
            cell: { col, _ in
                let period = periods[col]
                periodCell(period, cellSize: cellSize)
            }
        )
        .padding(.vertical, 4)
        .padding(.horizontal, 4)

        return GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    grid
                    Spacer(minLength: 0)
                }
                .frame(minWidth: geo.size.width)
            }
            .defaultScrollAnchor(.trailing)
        }
        .frame(height: monthlyHeatmapContentHeight)
    }

    // MARK: Single row (generic, used elsewhere if needed)

    private func singleRowHeatmap(
        periods: [Heatmap.PeriodData],
        columnLabel: @escaping (Heatmap.PeriodData) -> String,
        cellSize: CGFloat = cellSize
    ) -> some View {
        HStack(alignment: .top, spacing: cellSpacing) {
            Color.clear.frame(width: 0, height: 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: cellSpacing) {
                    ForEach(periods) { period in
                        VStack(spacing: cellSpacing) {
                            Text(columnLabel(period))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: cellSize, height: 18, alignment: .center)
                            periodCell(period, cellSize: cellSize)
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.trailing, 4)
            }
            .defaultScrollAnchor(.trailing)
        }
    }

    private static func periodColumnLabel(_ period: Heatmap.PeriodData, kind: CycleKind) -> String {
        let fmt = DateFormatter()
        switch kind {
        case .daily: fmt.dateFormat = "MMM d"
        case .weekly: fmt.dateFormat = "MM/dd"
        case .monthly: fmt.dateFormat = "MM/dd"
        }
        return fmt.string(from: period.periodStartPsychDay)
    }

    // MARK: Helpers – daily grid layout + month labels

    private static func buildDailyColumns(
        from periods: [Heatmap.PeriodData]
    ) -> [[Heatmap.PeriodData?]] {
        let cal = Time.calendar

        guard let firstPeriod = periods.first else {
            return []
        }

        let firstWeekday = cal.component(.weekday, from: firstPeriod.periodStartPsychDay)  // 1=Sun…7=Sat
        let firstOffset = (firstWeekday + 5) % 7  // 0=Mon, 6=Sun
        let weeksToShow = (firstOffset + periods.count + 6) / 7

        // Fill the first and last week with nil if they are not full.
        var flat: [Heatmap.PeriodData?] = Array(repeating: nil, count: weeksToShow * 7)
        for (i, period) in periods.enumerated() {
            let idx = firstOffset + i
            if idx < flat.count {
                flat[idx] = period
            }
        }

        // Convert flat buffer into 2D columns (weeks) × rows (days).
        var columns = Array(
            repeating: [Heatmap.PeriodData?](repeating: nil, count: 7), count: weeksToShow)
        for week in 0..<weeksToShow {
            for day in 0..<7 {
                let idx = week * 7 + day
                columns[week][day] = flat[idx]
            }
        }

        return columns
    }

    private static func buildMonthLabelsByColumn(
        from columns: [[Heatmap.PeriodData?]]
    ) -> [Int: String] {
        let cal = Time.calendar

        // Month labels centered over spans of weeks that belong to the same month.
        var monthStartWeeks: [(weekIdx: Int, date: Date)] = []
        for (weekIdx, column) in columns.enumerated() {
            // First non-nil day in that week.
            guard let first = column.compactMap({ $0 }).first else { continue }
            if weekIdx == 0 {
                monthStartWeeks.append((weekIdx, first.periodStartPsychDay))
                continue
            }
            guard let prevFirst = columns[weekIdx - 1].compactMap({ $0 }).first else {
                continue
            }
            if cal.component(.month, from: first.periodStartPsychDay)
                != cal.component(.month, from: prevFirst.periodStartPsychDay)
            {
                // Month has changed from last week to current week.
                monthStartWeeks.append((weekIdx, first.periodStartPsychDay))
            }
        }

        let monthFormatter: DateFormatter = {
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM"
            return fmt
        }()

        var monthLabelsByColumn: [Int: String] = [:]
        for (i, start) in monthStartWeeks.enumerated() {
            let endIdx =
                i + 1 < monthStartWeeks.count
                // Not the last month: ends at the week just before the next start.
                ? monthStartWeeks[i + 1].weekIdx - 1
                    // Last month ends at the last column.
                : columns.count - 1
            let midIdx = (start.weekIdx + endIdx) / 2
            monthLabelsByColumn[midIdx] = monthFormatter.string(from: start.date)
        }

        return monthLabelsByColumn
    }

    // MARK: Shared cell

    private func periodCell(
        _ period: Heatmap.PeriodData, cellSize: CGFloat = cellSize
    ) -> some View {
        let isSelected = selectedPeriod?.id == period.id
        let color = Heatmap.cellColor(for: period)
        return RoundedRectangle(cornerRadius: 2)
            .fill(period.isCurrent && !isSelected ? Color(.systemGray5) : color)
            .opacity(period.isBeforeCreation ? 0.7 : 1.0)
            .frame(width: cellSize, height: cellSize)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                } else if period.isCurrent {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(color, lineWidth: 1.5)
                }
            }
            .onTapGesture {
                guard !period.isFuture else { return }
                selectedPeriod = selectedPeriod?.id == period.id ? nil : period
            }
    }

    // MARK: Info card

    @ViewBuilder
    private func periodInfoCard(for period: Heatmap.PeriodData) -> some View {
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
                    if let goal = period.goal {
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
                            period.checkIns.map { timeString($0.psychDay) }.joined(
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

    private func timeString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        fmt.dateStyle = .none
        return fmt.string(from: date)
    }
}

// MARK: Info card

// MARK: - Mini row for compact views (Stage row, etc.)

struct MiniCommitmentHeatmapRow: View {
    let commitment: Commitment
    let daysToShow: Int

    private var psychToday: Date {
        Time.startOfDay(for: Time.now())
    }

    private var createdPsychDay: Date {
        Time.startOfDay(for: commitment.createdAt)
    }

    private var completionsByDay: [Date: Int] {
        var dict: [Date: Int] = [:]
        for ci in commitment.checkIns {
            dict[ci.psychDay, default: 0] += 1
        }
        return dict
    }

    private var periods: [Heatmap.PeriodData] {
        let cal = Time.calendar
        return (0..<daysToShow).map { offset in
            let date = cal.date(byAdding: .day, value: -(daysToShow - 1 - offset), to: psychToday)!
            let start = cal.startOfDay(for: date)
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? start

            let period = Heatmap.PeriodData(
                id: start,
                periodStartPsychDay: start,
                periodEndPsychDay: end,
                goal: nil,
                checkIns: commitment.checkInsInRange(
                    startPsychDay: start, endPsychDay: end),
                isBeforeCreation: date < createdPsychDay,
            )
            return period
        }
    }

    var body: some View {
        HStack(spacing: cellSpacing) {
            ForEach(Array(periods.enumerated()), id: \.offset) { _, period in
                let color = Heatmap.cellColor(for: period)

                RoundedRectangle(cornerRadius: 2)
                    .fill(period.isCurrent ? Color(.systemGray5) : color)
                    .frame(width: cellSize, height: cellSize)
                    .overlay {
                        if period.isCurrent {
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(color, lineWidth: 1.5)
                        }
                    }
            }
        }
    }
}

// MARK: - Preview factory

/// Shared preview data factory. Internal so CommitmentDetailView previews can reuse it.
enum HeatmapPreviewFactory {
    /// Commitment created 10 weeks ago, 70 days of varied check-in history (goal = 2×/day).
    /// Returns only the container; use a preview wrapper with @Query to get a live Commitment at render time.
    static func richHistoryContainer() -> ModelContainer {
        let container = try! ModelContainer(
            for: Commitment.self, Slot.self, CheckIn.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let cal = Calendar.current

        let createdAt =
            cal.date(byAdding: .day, value: -70, to: cal.startOfDay(for: Date())) ?? Date()
        let commitment = Commitment(
            title: "Morning Run",
            createdAt: createdAt,
            slots: [],
            target: Target(cycle: Cycle.anchored(.daily, at: .now), count: 2),
        )
        ctx.insert(commitment)

        let today = cal.startOfDay(for: Date())
        for dayOffset in 0..<70 {
            guard let date = cal.date(byAdding: .day, value: -dayOffset, to: today) else {
                continue
            }
            let weekday = cal.component(.weekday, from: date)
            let week = dayOffset / 7

            let count: Int
            switch (weekday, week % 4) {
            case (1, _): count = 0  // Sun: missed every week
            case (2, _): count = 2  // Mon: always goal
            case (3, 0), (3, 1): count = 1  // Tue: partial
            case (3, 2): count = 3  // Tue: over goal
            case (3, _): count = 2  // Tue: goal
            case (4, _): count = 3  // Wed: always over goal
            case (5, 0), (5, 1): count = 2  // Thu: goal
            case (5, 2): count = 1  // Thu: partial
            case (5, _): count = 0  // Thu: missed
            case (6, 0): count = 3  // Fri: over
            case (6, 1): count = 2  // Fri: goal
            case (6, 2): count = 1  // Fri: partial
            case (6, _): count = 0  // Fri: missed
            case (7, _): count = 2  // Sat: always goal
            default: count = 0
            }

            for _ in 0..<count {
                ctx.insert(CheckIn(commitment: commitment, createdAt: date))
            }
        }

        return container
    }

    /// Brand-new commitment created today with no check-in history.
    /// Returns only the container; use a preview wrapper with @Query to get a live Commitment at render time.
    static func newCommitmentContainer() -> ModelContainer {
        let container = try! ModelContainer(
            for: Commitment.self, Slot.self, CheckIn.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let commitment = Commitment(
            title: "Meditate",
            slots: [],
            target: Target(cycle: Cycle.anchored(.daily, at: .now), count: 2),
        )
        container.mainContext.insert(commitment)
        return container
    }
}

// MARK: - Preview helpers

/// Fetches the first commitment from the container at render time so the model reference stays valid
/// after preview context resets. Use this for any preview that needs a single Commitment (e.g. CommitmentDetailView).
struct PreviewWithFirstCommitment<Content: View>: View {
    let container: ModelContainer
    @ViewBuilder let content: (Commitment) -> Content

    var body: some View {
        PreviewWithFirstCommitmentInner(content: content)
            .modelContainer(container)
    }
}

struct PreviewWithFirstCommitmentInner<Content: View>: View {
    @Query private var commitments: [Commitment]
    @ViewBuilder let content: (Commitment) -> Content

    var body: some View {
        if let commitment = commitments.first {
            content(commitment)
        } else {
            Text("No commitment")
        }
    }
}

// MARK: - Previews

#Preview("Rich history") {
    let container = HeatmapPreviewFactory.richHistoryContainer()
    PreviewWithFirstCommitment(container: container) { commitment in
        CommitmentHeatmapView(commitment: commitment)
    }
    .padding()
}

#Preview("New commitment (no history)") {
    let container = HeatmapPreviewFactory.newCommitmentContainer()
    PreviewWithFirstCommitment(container: container) { commitment in
        CommitmentHeatmapView(commitment: commitment)
    }
    .padding()
}
