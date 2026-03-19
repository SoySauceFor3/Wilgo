import Foundation

// Derive an expected goal per heatmap period from the commitment's target cycle.
// Fractions are always rounded up so very small expectations (e.g. 1/7 per day)
// still show as at least 1.
func expectedGoalPerPeriod(target: Target, periodKind: CycleKind) -> Int? {
    let baseCount = target.count
    if baseCount <= 0 { return nil }

    let targetKind = target.cycle.kind

    func ceilDiv(_ numerator: Double, _ denominator: Double) -> Int {
        Int(ceil(numerator / denominator))
    }

    switch (targetKind, periodKind) {
    case (.daily, .daily):
        return baseCount
    case (.daily, .weekly):
        return baseCount * 7
    case (.daily, .monthly):
        // Approximate month length; we only need a stable mapping.
        return baseCount * 30

    case (.weekly, .daily):
        return ceilDiv(Double(baseCount), 7.0)
    case (.weekly, .weekly):
        return baseCount
    case (.weekly, .monthly):
        // Roughly 4 weeks per month.
        return baseCount * 4

    case (.monthly, .daily):
        return ceilDiv(Double(baseCount), 30.0)
    case (.monthly, .weekly):
        // Approximate 4 weeks per month.
        return ceilDiv(Double(baseCount), 4.0)
    case (.monthly, .monthly):
        return baseCount
    }
}

struct HeatmapPeriodData: Identifiable {
    let id: Date  // periodStart as identity
    let periodStartPsychDay: Date
    let periodEndPsychDay: Date  // exclusive

    let goal: Int?  // nil when target cycle kind != heatmap kind
    let checkIns: [CheckIn]
    let isBeforeCreation: Bool

    var isCurrent: Bool {
        let today = CommitmentScheduling.psychDay(for: CommitmentScheduling.now())
        return periodStartPsychDay <= today && today < periodEndPsychDay
    }

    var isFuture: Bool {
        let today = CommitmentScheduling.psychDay(for: CommitmentScheduling.now())
        return periodStartPsychDay > today
    }
}

// MARK: - Shared context for heatmap builders

struct HeatmapContext {
    let commitment: Commitment

    var today: Date { CommitmentScheduling.psychDay(for: CommitmentScheduling.now()) }
    var createdPsychDay: Date { CommitmentScheduling.psychDay(for: commitment.createdAt) }
    var target: Cycle { commitment.target.cycle }
    var cal: Calendar { CommitmentScheduling.calendar }

    var checkInTimesByDay: [Date: [Date]] {
        var d: [Date: [Date]] = [:]
        for ci in commitment.checkIns {
            let key = cal.startOfDay(for: ci.psychDay)
            d[key, default: []].append(ci.createdAt)
        }
        for k in d.keys { d[k]?.sort() }
        return d
    }
}

// MARK: - Mode-specific builders

struct DailyHeatmapDataBuilder {
    let context: HeatmapContext
    let daysToShow = 180

    private var psychToday: Date { context.today }
    private var createdPsychDay: Date { context.createdPsychDay }
    private var target: Cycle { context.target }
    private var cal: Calendar { context.cal }

    /// Expected goal per day derived from the commitment's target cycle.
    private var goalForPeriod: Int? {
        expectedGoalPerPeriod(target: context.commitment.target, periodKind: .daily)
    }

    /// Returns day-sized periods for the daily heatmap, ordered by today to oldest date. The UI is responsible for shaping these into a grid
    /// and computing labels.
    func dailyPeriods() -> [HeatmapPeriodData] {
        let goal = goalForPeriod

        var periods: [HeatmapPeriodData] = []

        for c in (-daysToShow + 1)...0 {
            guard let gridDate = cal.date(byAdding: .day, value: c, to: psychToday)  // guaranteed to be the start of the day because psychToday is.
            else {
                continue
            }

            let start = gridDate
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
            periods.append(
                HeatmapPeriodData(
                    id: start,
                    periodStartPsychDay: start,
                    periodEndPsychDay: end,
                    goal: goal,
                    checkIns: context.commitment.checkInsInRange(
                        startPsychDay: start, endPsychDay: end),
                    isBeforeCreation: end < createdPsychDay
                )
            )
        }
        return periods
    }
}

struct WeeklyHeatmapDataBuilder {
    let context: HeatmapContext
    let weeksToShow = 26

    private var today: Date { context.today }
    private var createdPsychDay: Date { context.createdPsychDay }
    private var target: Cycle { context.target }
    private var cal: Calendar { context.cal }

    /// Expected goal per week derived from the commitment's target cycle.
    private var goalForPeriod: Int? {
        expectedGoalPerPeriod(target: context.commitment.target, periodKind: .weekly)
    }

    func weeklyPeriods() -> [HeatmapPeriodData] {
        let cycle: Cycle = {
            if target.kind == .weekly { return target }
            return Cycle(
                kind: .weekly,
                referencePsychDay: CommitmentScheduling.calendar.date(
                    from: DateComponents(year: 2026, month: 3, day: 2))!)  // 03/02/2026 is a Monday
        }()
        let currentStart = cycle.startDayOfCycle(including: today)
        guard
            let firstStart = cal.date(
                byAdding: .day, value: -7 * (weeksToShow - 1), to: currentStart)
        else {
            return []
        }
        var periods: [HeatmapPeriodData] = []
        var start = firstStart
        for _ in 0..<weeksToShow {
            let end = cycle.endDayOfCycle(including: start)
            let checkIns = context.commitment.checkInsInRange(
                startPsychDay: start, endPsychDay: end)
            periods.append(
                HeatmapPeriodData(
                    id: start,
                    periodStartPsychDay: start,
                    periodEndPsychDay: end,
                    goal: goalForPeriod,
                    checkIns: checkIns,
                    isBeforeCreation: end < createdPsychDay
                ))
            start = end
        }
        return periods
    }
}

struct MonthlyHeatmapDataBuilder {
    let context: HeatmapContext
    let monthsToShow = 12

    private var today: Date { context.today }
    private var createdPsychDay: Date { context.createdPsychDay }
    private var target: Cycle { context.target }
    private var cal: Calendar { context.cal }

    /// Expected goal per month derived from the commitment's target cycle.
    private var goalForPeriod: Int? {
        expectedGoalPerPeriod(target: context.commitment.target, periodKind: .monthly)
    }

    func monthlyPeriods() -> [HeatmapPeriodData] {
        let cycle: Cycle = {
            if target.kind == .monthly { return target }
            return Cycle(
                kind: .monthly,
                referencePsychDay: CommitmentScheduling.calendar.date(
                    from: DateComponents(year: 2026, month: 3, day: 1))!)  // 03/01/2026 is the first day of the month
        }()
        var currentStart = cycle.startDayOfCycle(including: today)
        for _ in 0..<(monthsToShow - 1) {
            guard let prevDay = cal.date(byAdding: .day, value: -1, to: currentStart) else { break }
            currentStart = cycle.startDayOfCycle(including: prevDay)
        }
        var periods: [HeatmapPeriodData] = []
        var start = currentStart
        for _ in 0..<monthsToShow {
            let end = cycle.endDayOfCycle(including: start)
            let checkIns = context.commitment.checkInsInRange(
                startPsychDay: start, endPsychDay: end)
            periods.append(
                HeatmapPeriodData(
                    id: start,
                    periodStartPsychDay: start,
                    periodEndPsychDay: end,
                    goal: goalForPeriod,
                    checkIns: checkIns,
                    isBeforeCreation: end < createdPsychDay
                ))
            start = end
        }
        return periods
    }
}
