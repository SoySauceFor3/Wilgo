import SwiftData
import SwiftUI

// MARK: - Day data

private struct HeatmapDayData {
    let date: Date
    let completedCount: Int
    let goal: Int
    let isBeforeCreation: Bool
    let isFuture: Bool
    let isToday: Bool
}

// MARK: - View

struct HabitHeatmapView: View {
    let habit: Habit

    @State private var selectedDay: HeatmapDayData? = nil

    private let weeksToShow = 26
    private let cellSize: CGFloat = 11
    private let cellSpacing: CGFloat = 3
    private let dowLabels = ["S", "M", "T", "W", "T", "F", "S"]

    // MARK: Derived data

    private var today: Date {
        HabitScheduling.psychDay(for: HabitScheduling.now())
    }

    private var createdPsychDay: Date {
        HabitScheduling.psychDay(for: habit.createdAt)
    }

    /// O(checkIns.count) lookup table so we don't scan all check-ins per cell.
    private var completionsByDay: [Date: Int] {
        var dict: [Date: Int] = [:]
        for ci in habit.checkIns {
            dict[ci.psychDay, default: 0] += 1
        }
        return dict
    }

    /// Maps each psych day to its check-in timestamps, sorted ascending.
    private var checkInTimesByDay: [Date: [Date]] {
        var dict: [Date: [Date]] = [:]
        for ci in habit.checkIns {
            dict[ci.psychDay, default: []].append(ci.createdAt)
        }
        for key in dict.keys { dict[key]?.sort() }
        return dict
    }

    /// 26 columns (oldest → newest), each column = 7 days (Sun=0 … Sat=6).
    private var weekColumns: [[HeatmapDayData?]] {
        let todayDate = today
        let createdDate = createdPsychDay
        let counts = completionsByDay
        let goal = max(1, habit.timesPerDay)
        let cal = Calendar.current

        // Snap to the Sunday that starts the current week.
        let todayWeekday = cal.component(.weekday, from: todayDate)  // 1=Sun … 7=Sat
        guard
            let thisSunday = cal.date(byAdding: .day, value: -(todayWeekday - 1), to: todayDate),
            let startSunday = cal.date(
                byAdding: .weekOfYear, value: -(weeksToShow - 1), to: thisSunday)
        else { return [] }

        return (0..<weeksToShow).map { weekOffset in
            guard let weekStart = cal.date(byAdding: .day, value: weekOffset * 7, to: startSunday)
            else { return [HeatmapDayData?](repeating: nil, count: 7) }
            return (0..<7).map { dayOffset in
                guard let date = cal.date(byAdding: .day, value: dayOffset, to: weekStart)
                else { return nil }
                return HeatmapDayData(
                    date: date,
                    completedCount: counts[date] ?? 0,
                    goal: goal,
                    isBeforeCreation: date < createdDate,
                    isFuture: date > todayDate,
                    isToday: date == todayDate
                )
            }
        }
    }

    // MARK: Month label helpers

    /// Maps each column index to a month abbreviation, positioned at the midpoint of
    /// that month's visible column span so labels appear centered over their month.
    private var monthLabelsByColumn: [Int: String] {
        let cal = Calendar.current

        // Collect the start column index for each month boundary.
        var starts: [(weekIdx: Int, date: Date)] = []
        for weekIdx in 0..<weekColumns.count {
            guard let first = weekColumns[weekIdx].compactMap({ $0 }).first else { continue }
            if weekIdx == 0 {
                starts.append((weekIdx, first.date))
                continue
            }
            guard let prevFirst = weekColumns[weekIdx - 1].compactMap({ $0 }).first else {
                continue
            }
            if cal.component(.month, from: first.date)
                != cal.component(.month, from: prevFirst.date)
            {
                starts.append((weekIdx, first.date))
            }
        }

        // Place each label at the midpoint of its month's column span.
        var result: [Int: String] = [:]
        for (i, start) in starts.enumerated() {
            let endIdx = i + 1 < starts.count ? starts[i + 1].weekIdx - 1 : weekColumns.count - 1
            let midIdx = (start.weekIdx + endIdx) / 2
            result[midIdx] = monthAbbr(start.date)
        }
        return result
    }

    private func monthAbbr(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM"
        return fmt.string(from: date)
    }

    // MARK: Color

    private func cellColor(for day: HeatmapDayData) -> Color {
        if day.isFuture { return .clear }
        if day.isBeforeCreation { return Color(.systemGray5) }

        let goal = day.goal
        let count = day.completedCount

        switch count {
        case 0:
            // Most eye-catching — worst-day red
            return Color(hue: 0.02, saturation: 0.88, brightness: 0.80)

        case 1..<goal:
            // Red scale: vivid at 1, fades to near-neutral approaching goal
            let ratio = Double(count) / Double(goal)
            return Color(
                hue: 0.02,
                saturation: 0.88 * (1 - ratio) + 0.15 * ratio,
                brightness: 0.80 + 0.15 * ratio
            )

        default:
            // Green scale: base green at goal, deepens with each extra check-in (up to +3)
            let ratio = min(Double(count - goal) / 3.0, 1.0)
            return Color(
                hue: 0.37,
                saturation: 0.50 + 0.42 * ratio,
                brightness: 0.72 - 0.22 * ratio
            )
        }
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: cellSpacing) {
                // Day-of-week labels — fixed outside the scroll view so they stay visible
                VStack(spacing: cellSpacing) {
                    Color.clear.frame(width: cellSize, height: 14)  // aligns with month row
                    ForEach(dowLabels.indices, id: \.self) { i in
                        Text(dowLabels[i])
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .frame(width: cellSize, height: cellSize)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: cellSpacing) {
                        ForEach(0..<weekColumns.count, id: \.self) { weekIdx in
                            VStack(spacing: cellSpacing) {
                                // Fixed-width anchor keeps all columns equal-width.
                                // Label is centered on the midpoint column of its month,
                                // so it reads as centered over the month section.
                                Color.clear
                                    .frame(width: cellSize, height: 14)
                                    .overlay(alignment: .center) {
                                        if let label = monthLabelsByColumn[weekIdx] {
                                            Text(label)
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundStyle(.secondary)
                                                .fixedSize()
                                        }
                                    }

                                ForEach(0..<7, id: \.self) { dayIdx in
                                    if let day = weekColumns[weekIdx][dayIdx] {
                                        cellView(for: day)
                                    } else {
                                        Color.clear.frame(width: cellSize, height: cellSize)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.trailing, 4)  // Room for month labels and rightmost cells to overflow without clipping
                }
                .defaultScrollAnchor(.trailing)
            }

            legendView

            // Info card — slides in when a day is tapped
            if let selected = selectedDay {
                dayInfoCard(for: selected)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

        }
        .animation(.spring(duration: 0.22), value: selectedDay?.date)
    }

    // MARK: Cell view

    @ViewBuilder
    private func cellView(for day: HeatmapDayData) -> some View {
        let isSelected = selectedDay?.date == day.date
        let semanticColor = cellColor(for: day)
        // Today: hollow — light gray fill, semantic-color border.
        // Selected: normal fill, white selection ring on top.
        RoundedRectangle(cornerRadius: 2)
            .fill(day.isToday && !isSelected ? Color(.systemGray5) : semanticColor)
            .opacity(day.isBeforeCreation ? 0.35 : 1.0)
            .frame(width: cellSize, height: cellSize)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                } else if day.isToday {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(semanticColor, lineWidth: 1.5)
                }
            }
            .onTapGesture {
                guard !day.isFuture else { return }
                selectedDay = selectedDay?.date == day.date ? nil : day
            }
    }

    // MARK: Info card

    @ViewBuilder
    private func dayInfoCard(for day: HeatmapDayData) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Colored dot matching the cell
            RoundedRectangle(cornerRadius: 2)
                .fill(cellColor(for: day).opacity(day.isBeforeCreation ? 0.35 : 1.0))
                .frame(width: 9, height: 9)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDate(day.date))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                if day.isBeforeCreation {
                    Text("Before tracking started")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(day.completedCount) / \(day.goal)")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.primary)
                        Text(statusLabel(for: day))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    let times = checkInTimesByDay[day.date] ?? []
                    if !times.isEmpty {
                        Text(times.map { timeString($0) }.joined(separator: "  ·  "))
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
        .onTapGesture {
            selectedDay = nil
        }
    }

    // MARK: Info card helpers

    private func formattedDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE, MMM d"
        return fmt.string(from: date)
    }

    private func statusLabel(for day: HeatmapDayData) -> String {
        let c = day.completedCount
        let g = day.goal
        if c == 0 { return "Missed" }
        if c < g { return "Partial" }
        if c == g { return "Goal met ✓" }
        return "+\(c - g) over goal"
    }

    private func timeString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        fmt.dateStyle = .none
        return fmt.string(from: date)
    }

    // MARK: Legend

    private var legendView: some View {
        HStack(spacing: 8) {
            legendItem(
                Color(.systemGray5), "Today",
                borderColor: Color.primary.opacity(0.45))
            legendItem(Color(.systemGray5).opacity(0.35), "N/A")
            legendItem(Color(hue: 0.02, saturation: 0.88, brightness: 0.80), "Missed")
            legendItem(Color(hue: 0.02, saturation: 0.40, brightness: 0.92), "Partial")
            legendItem(Color(hue: 0.37, saturation: 0.50, brightness: 0.72), "Goal")
            legendItem(Color(hue: 0.37, saturation: 0.92, brightness: 0.50), "Over")
        }
    }

    private func legendItem(_ color: Color, _ label: String, borderColor: Color? = nil) -> some View
    {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: cellSize, height: cellSize)
                .overlay {
                    if let bc = borderColor {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(bc, lineWidth: 1.5)
                    }
                }
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview factory

/// Shared preview data factory. Internal so HabitDetailView previews can reuse it.
enum HeatmapPreviewFactory {
    /// Habit created 10 weeks ago, 70 days of varied check-in history (goal = 2×/day).
    static func richHistory() -> (ModelContainer, Habit) {
        let container = try! ModelContainer(
            for: Habit.self, HabitSlot.self, HabitCheckIn.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let cal = Calendar.current

        let createdAt =
            cal.date(byAdding: .day, value: -70, to: cal.startOfDay(for: Date())) ?? Date()
        let slot1 = HabitSlot(
            start: cal.date(from: DateComponents(hour: 6)) ?? Date(),
            end: cal.date(from: DateComponents(hour: 8)) ?? Date()
        )
        let slot2 = HabitSlot(
            start: cal.date(from: DateComponents(hour: 17)) ?? Date(),
            end: cal.date(from: DateComponents(hour: 19)) ?? Date()
        )
        let habit = Habit(
            title: "Morning Run",
            createdAt: createdAt,
            slots: [slot1, slot2],
            skipCreditCount: 3,
            cycle: .weekly(weekday: 2)
        )
        ctx.insert(habit)
        ctx.insert(slot1)
        ctx.insert(slot2)

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
                ctx.insert(HabitCheckIn(habit: habit, createdAt: date))
            }
        }

        return (container, habit)
    }

    /// Brand-new habit created today with no check-in history.
    static func newHabit() -> (ModelContainer, Habit) {
        let container = try! ModelContainer(
            for: Habit.self, HabitSlot.self, HabitCheckIn.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let cal = Calendar.current
        let slot = HabitSlot(
            start: cal.date(from: DateComponents(hour: 8)) ?? Date(),
            end: cal.date(from: DateComponents(hour: 9)) ?? Date()
        )
        let habit = Habit(title: "Meditate", slots: [slot], skipCreditCount: 1, cycle: .daily)
        container.mainContext.insert(habit)
        container.mainContext.insert(slot)
        return (container, habit)
    }
}

// MARK: - Previews

#Preview("Rich history") {
    let (container, habit) = HeatmapPreviewFactory.richHistory()
    HabitHeatmapView(habit: habit)
        .padding()
        .modelContainer(container)
}

#Preview("New habit (no history)") {
    let (container, habit) = HeatmapPreviewFactory.newHabit()
    HabitHeatmapView(habit: habit)
        .padding()
        .modelContainer(container)
}
