import Foundation
import SwiftData

// NOTE: the date here should ignore hour and minute, and should treat date as PsychDate.

/// The kind of reset cycle, without any anchor data. Used as the Picker selection type.
enum CycleKind: String, CaseIterable, Codable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"

    var nounSingle: String {
        switch self {
        case .daily: return "Day"
        case .weekly: return "Week"
        case .monthly: return "Month"
        }
    }

    var nounPlural: String {
        switch self {
        case .daily: return "Days"
        case .weekly: return "Weeks"
        case .monthly: return "Months"
        }
    }

    var adj: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    var thisNoun: String {
        switch self {
        case .daily: return "today"
        case .weekly: return "this week"
        case .monthly: return "this month"
        }
    }
}

/// A reset cycle anchored at a specific reference date.
///
/// - `kind`:       daily / weekly / monthly.
/// - `multiplier`: how many base cycles are grouped into one period (e.g. 2 weeks, 3 months).
/// - `referenceDate`: any psych-day within the first period; this defines the anchor.
struct Cycle: Codable, Equatable, Hashable {
    var kind: CycleKind
    private var referencePsychDay: Date  // psych-day; hour/minute ignored; it is one of the start day of the Cycle.
    var multiplier: Int

    init(kind: CycleKind, referencePsychDay: Date, multiplier: Int = 1, ) {
        self.kind = kind
        self.referencePsychDay = referencePsychDay
        self.multiplier = max(1, multiplier)
    }

    func periodicRepresentation() -> String {
        if multiplier == 1 {
            return "\(multiplier) \(kind.nounSingle)"
        }
        return "\(multiplier) \(kind.nounPlural)"

    }

    /// Human-readable period label for the cycle period containing `date`.
    ///
    /// - Daily (multiplier=1): "Mar 4"
    /// - Other cases:          "Mar 2 – Mar 8"
    func label(of date: Date = Time.now()) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM/dd"
        let start = self.startDayOfCycle(including: date)

        // Single-day period → use compact single-date label.
        if kind == .daily && multiplier == 1 {
            return fmt.string(from: start)
        }

        let cal = Time.calendar
        let exclusiveEnd = self.endDayOfCycle(including: date)
        let inclusiveEnd = cal.date(byAdding: .day, value: -1, to: exclusiveEnd) ?? exclusiveEnd
        return "\(fmt.string(from: start)) – \(fmt.string(from: inclusiveEnd))"
    }
}

// MARK: - Cycle period boundaries

extension Cycle {
    // TODO: remove this function.
    /// Returns a cycle who start on `time`'s psych-day.
    static func anchored(_ kind: CycleKind, at time: Date, multiplier: Int = 1) -> Cycle {
        let psychDay = Time.psychDay(for: time)
        return Cycle(kind: kind, referencePsychDay: psychDay, multiplier: multiplier)
    }

    /// Creates a `Cycle` anchored to the canonical start day for the given kind:
    /// - `.daily`   → today's psych-day (same as `anchored`)
    /// - `.weekly`  → most recent Monday on or before `date`
    /// - `.monthly` → 1st of the month containing `date`
    ///
    /// Use this as the intercepting factory for new commitments and rule edits
    /// so that weekly cycles always start on Monday and monthly cycles on the 1st.
    /// Existing `Cycle` instances and `anchored(_:at:)` are unaffected.
    static func makeDefault(_ kind: CycleKind, on date: Date = Time.now()) -> Cycle {
        let psychDay = Time.psychDay(for: date)
        let anchor: Date
        switch kind {
        case .daily:
            anchor = psychDay
        case .weekly:
            // weeklyPeriodStart(matches: 2, ...) → most recent Monday (1=Sun, 2=Mon …)
            anchor = weeklyPeriodStart(matches: 2, of: psychDay)
        case .monthly:
            // monthlyPeriodStart(matches: 1, ...) → 1st of the containing month
            anchor = monthlyPeriodStart(matches: 1, of: psychDay)
        }
        return Cycle(kind: kind, referencePsychDay: anchor)
    }

    /// Start of the (multiplier × base-kind) period that contains `date`.
    func startDayOfCycle(including psychDay: Date = Time.now()) -> Date {
        let cal = Time.calendar
        let psychDay = cal.startOfDay(for: psychDay)
        var cycleStartReference = cal.startOfDay(for: referencePsychDay)

        func stepForward(from current: Date) -> Date {
            switch kind {
            case .daily:
                return cal.date(byAdding: .day, value: multiplier, to: current) ?? current
            case .weekly:
                return cal.date(byAdding: .day, value: 7 * multiplier, to: current) ?? current
            case .monthly:
                let anchorDay = cal.component(.day, from: referencePsychDay)
                var result = current
                for _ in 0..<multiplier {
                    result = Cycle.nextMonthlyDay(on: anchorDay, after: result)
                }
                return result
            }
        }

        func stepBackward(from current: Date) -> Date {
            switch kind {
            case .daily:
                return cal.date(byAdding: .day, value: -multiplier, to: current) ?? current
            case .weekly:
                return cal.date(byAdding: .day, value: -7 * multiplier, to: current) ?? current
            case .monthly:
                let anchorDay = cal.component(.day, from: referencePsychDay)
                var result = current
                for _ in 0..<multiplier {
                    // Go back one base month at a time.
                    let prevMonth =
                        cal.date(byAdding: .month, value: -1, to: result) ?? result
                    result =
                        Cycle.clampedMonthDay(anchorDay, inMonthOf: prevMonth, cal: cal)
                        ?? prevMonth
                }
                return result
            }
        }

        if psychDay >= cycleStartReference {
            // cycleStartReference <= ans <= psychDay < next
            while true {
                let next = stepForward(from: cycleStartReference)
                if psychDay < next { break }
                cycleStartReference = next
            }
            return cycleStartReference
        } else {
            // ans <= psychDay < cycleStartReference
            // prev <= psychDay
            while true {
                let prev = stepBackward(from: cycleStartReference)
                if psychDay >= prev {
                    return prev  // found the previous cycle start reference
                }
                cycleStartReference = prev
            }
        }
    }

    /// Exclusive end of the budget period (multiplier × base-kind) of `date` (i.e. next period start).
    func endDayOfCycle(including psychDay: Date = Time.now()) -> Date {
        let start = startDayOfCycle(including: psychDay)
        let cal = Time.calendar
        switch kind {
        case .daily:
            return cal.date(byAdding: .day, value: multiplier, to: start) ?? start
        case .weekly:
            return cal.date(byAdding: .day, value: 7 * multiplier, to: start) ?? start
        case .monthly:
            let anchorDay = cal.component(.day, from: referencePsychDay)
            var result = start
            for _ in 0..<multiplier {
                result = Cycle.nextMonthlyDay(on: anchorDay, after: result)
            }
            return result
        }
    }

    // MARK: - Private: Anchor-based period math

    /// Most recent date on or before `date` whose weekday matches `anchorWeekday` (1 = Sun … 7 = Sat).
    private static func weeklyPeriodStart(matches anchorWeekday: Int, of date: Date) -> Date {
        let cal = Time.calendar
        let currWeekday = cal.component(.weekday, from: cal.startOfDay(for: date))
        let daysBack = (currWeekday - anchorWeekday + 7) % 7
        return cal.date(byAdding: .day, value: -daysBack, to: cal.startOfDay(for: date))
            ?? cal.startOfDay(for: date)
    }

    /// Most recent date on or before `date` whose day-of-month matches `anchorDay` (1–31),
    /// clamped to the last day of the relevant month.
    private static func monthlyPeriodStart(matches anchorDay: Int, of date: Date) -> Date {
        let cal = Time.calendar
        let date = cal.startOfDay(for: date)

        // Try this calendar month first.
        if let candidate = clampedMonthDay(anchorDay, inMonthOf: date, cal: cal),
            cal.compare(candidate, to: date, toGranularity: .day) != .orderedDescending
        {
            return candidate
        }

        // Fall back to the previous calendar month.
        let prevMonth = cal.date(byAdding: .month, value: -1, to: date) ?? date
        return clampedMonthDay(anchorDay, inMonthOf: prevMonth, cal: cal)
            ?? cal.startOfDay(for: prevMonth)
    }

    /// Returns the date for day `targetDay` in the same month as `reference`, clamped to
    /// the last day of that month if `targetDay` exceeds the month's length.
    /// Returns `nil` only if calendar arithmetic fails entirely.
    static func clampedMonthDay(_ targetDay: Int, inMonthOf reference: Date, cal: Calendar) -> Date?
    {
        guard let range = cal.range(of: .day, in: .month, for: reference) else { return nil }
        let day = min(targetDay, range.count)
        var comps = cal.dateComponents([.year, .month], from: reference)
        comps.day = day
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return cal.date(from: comps)
    }

    /// Start of the monthly period that immediately follows `currentPeriodStart`.
    private static func nextMonthlyDay(on anchorDay: Int, after currentPeriodStart: Date)
        -> Date
    {
        let cal = Time.calendar
        let nextMonth =
            cal.date(byAdding: .month, value: 1, to: currentPeriodStart) ?? currentPeriodStart
        return clampedMonthDay(anchorDay, inMonthOf: nextMonth, cal: cal) ?? nextMonth
    }
}
