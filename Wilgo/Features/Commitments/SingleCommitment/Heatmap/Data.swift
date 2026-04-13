import Foundation

// Derive an expected goal per heatmap period from the commitment's target cycle.
// Fractions are always rounded up so very small expectations (e.g. 1/7 per day)
// still show as at least 1.
extension Heatmap {
    // Derive an expected goal per heatmap period from the commitment's target cycle.
    // Fractions are always rounded up so very small expectations (e.g. 1/7 per day)
    // still show as at least 1.
    static func expectedGoalPerPeriod(target: Target, periodKind: CycleKind) -> Int? {
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

    struct PeriodData: Identifiable {
        let id: Date  // periodStart as identity
        let periodStartPsychDay: Date
        let periodEndPsychDay: Date  // exclusive

        let goal: Int?  // nil when target cycle kind != heatmap kind
        let checkIns: [CheckIn]
        let isBeforeCreation: Bool

        var isCurrent: Bool {
            let today = Time.startOfDay(for: Time.now())
            return periodStartPsychDay <= today && today < periodEndPsychDay
        }

        var isFuture: Bool {
            let today = Time.startOfDay(for: Time.now())
            return periodStartPsychDay > today
        }
    }
}

// MARK: - Shared context for heatmap builders
extension Heatmap {
    struct Context {
        let commitment: Commitment

        var today: Date { Time.startOfDay(for: Time.now()) }
        var createdPsychDay: Date { Time.startOfDay(for: commitment.createdAt) }
        var target: Cycle { commitment.target.cycle }
        var cal: Calendar { Time.calendar }

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
}

// MARK: - Mode-specific builders
extension Heatmap {
    struct DailyDataBuilder {
        let context: Context
        let daysToShow = 180

        private var psychToday: Date { context.today }
        private var createdPsychDay: Date { context.createdPsychDay }
        private var target: Cycle { context.target }
        private var cal: Calendar { context.cal }

        /// Expected goal per day derived from the commitment's target cycle.
        private var goalForPeriod: Int? {
            Heatmap.expectedGoalPerPeriod(target: context.commitment.target, periodKind: .daily)
        }

        /// Returns day-sized periods for the daily heatmap, ordered by today to oldest date. The UI is responsible for shaping these into a grid
        /// and computing labels.
        func dailyPeriods() -> [PeriodData] {
            let goal = goalForPeriod

            var periods: [PeriodData] = []

            for c in (-daysToShow + 1)...0 {
                guard
                    let gridDate = cal.date(byAdding: .day, value: c, to: psychToday)  // start of day because psychToday is
                else {
                    continue
                }

                let start = gridDate
                let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
                periods.append(
                    PeriodData(
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
}

extension Heatmap {
    struct WeeklyDataBuilder {
        let context: Context
        let weeksToShow = 26

        private var today: Date { context.today }
        private var createdPsychDay: Date { context.createdPsychDay }
        private var target: Cycle { context.target }
        private var cal: Calendar { context.cal }

        /// Expected goal per week derived from the commitment's target cycle.
        private var goalForPeriod: Int? {
            Heatmap.expectedGoalPerPeriod(target: context.commitment.target, periodKind: .weekly)
        }

        func weeklyPeriods() -> [PeriodData] {
            let cycle: Cycle = {
                if target.kind == .weekly { return target }
                return Cycle(
                    kind: .weekly,
                    referencePsychDay: Time.calendar.date(
                        from: DateComponents(year: 2026, month: 3, day: 2))!)  // 03/02/2026 is a Monday
            }()
            let currentStart = cycle.startDayOfCycle(including: today)
            guard
                let firstStart = cal.date(
                    byAdding: .day, value: -7 * (weeksToShow - 1), to: currentStart)
            else {
                return []
            }
            var periods: [PeriodData] = []
            var start = firstStart
            for _ in 0..<weeksToShow {
                let end = cycle.endDayOfCycle(including: start)
                let checkIns = context.commitment.checkInsInRange(
                    startPsychDay: start, endPsychDay: end)
                periods.append(
                    PeriodData(
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
}

extension Heatmap {
    struct MonthlyDataBuilder {
        let context: Context
        let monthsToShow = 12

        private var today: Date { context.today }
        private var createdPsychDay: Date { context.createdPsychDay }
        private var target: Cycle { context.target }
        private var cal: Calendar { context.cal }

        /// Expected goal per month derived from the commitment's target cycle.
        private var goalForPeriod: Int? {
            Heatmap.expectedGoalPerPeriod(target: context.commitment.target, periodKind: .monthly)
        }

        func monthlyPeriods() -> [PeriodData] {
            let cycle: Cycle = {
                if target.kind == .monthly { return target }
                return Cycle(
                    kind: .monthly,
                    referencePsychDay: Time.calendar.date(
                        from: DateComponents(year: 2026, month: 3, day: 1))!)  // 03/01/2026 is the first day of the month
            }()
            var currentStart = cycle.startDayOfCycle(including: today)
            for _ in 0..<(monthsToShow - 1) {
                guard let prevDay = cal.date(byAdding: .day, value: -1, to: currentStart) else {
                    break
                }
                currentStart = cycle.startDayOfCycle(including: prevDay)
            }
            var periods: [PeriodData] = []
            var start = currentStart
            for _ in 0..<monthsToShow {
                let end = cycle.endDayOfCycle(including: start)
                let checkIns = context.commitment.checkInsInRange(
                    startPsychDay: start, endPsychDay: end)
                periods.append(
                    PeriodData(
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
}
