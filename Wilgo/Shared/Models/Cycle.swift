import Foundation
import SwiftData

// NOTE: the date here should ignore hour and minute, and should treat date as PsychDate.

/// The kind of reset cycle, without any anchor data. Used as the Picker selection type.
enum CycleKind: String, CaseIterable, Codable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
}

/// How often the commitment's skip-credit budget resets, with the anchor baked in.
///
/// - `.daily`:              resets at midnight every day; no anchor needed.
/// - `.weekly(weekday:)`:   resets on the given Calendar weekday (1 = Sun … 7 = Sat).
/// - `.monthly(day:)`:      resets on the given day-of-month (1–31), clamped for short months.
enum Cycle: Codable, Equatable, Hashable {
    case daily
    case weekly(weekday: Int)
    case monthly(day: Int)

    var kind: CycleKind {
        switch self {
        case .daily: return .daily
        case .weekly: return .weekly
        case .monthly: return .monthly
        }
    }

    /// Human-readable label, matches the old `Period.rawValue` usage.
    var label: String { kind.rawValue }

    /// Human-readable period label for the cycle containing `date`.
    ///
    /// - Daily:   "Mar 4"
    /// - Weekly:  "Mar 2 – Mar 8"
    /// - Monthly: "Mar 1 – Mar 31"  (respects custom anchor days, e.g. "Feb 15 – Mar 14")
    func label(of date: Date = CommitmentScheduling.now()) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let start = self.start(of: date)
        switch self {
        case .daily:
            return fmt.string(from: start)
        case .weekly, .monthly:
            let cal = CommitmentScheduling.calendar
            let exclusiveEnd = self.end(of: date)
            let inclusiveEnd = cal.date(byAdding: .day, value: -1, to: exclusiveEnd) ?? exclusiveEnd
            return "\(fmt.string(from: start)) – \(fmt.string(from: inclusiveEnd))"
        }
    }
}

// MARK: - Cycle period boundaries

extension Cycle {
    /// Returns a cycle whose period containing `time` starts on that time's psych-day.
    static func anchored(_ kind: CycleKind, at time: Date) -> Cycle {
        let psychDay = CommitmentScheduling.psychDay(for: time)
        let cal = CommitmentScheduling.calendar
        switch kind {
        case .daily:
            return .daily
        case .weekly:
            let weekday = cal.component(.weekday, from: psychDay)
            return .weekly(weekday: weekday)
        case .monthly:
            let day = cal.component(.day, from: psychDay)
            return .monthly(day: day)
        }
    }

    /// Start of the cycle of the mentioned date, derived from the cycle's configuration.
    ///
    /// - `.daily`:           start of the day of `date`.
    /// - `.weekly(weekday)`: most recent occurrence of that weekday on or before `date`.
    /// - `.monthly(day)`:    most recent occurrence of that day-of-month on or before `date`,
    ///   clamped to the last day of shorter months (e.g. day=31 → Feb 28/29).
    func start(of date: Date = CommitmentScheduling.now()) -> Date {
        switch self {
        case .daily:
            return CommitmentScheduling.calendar.startOfDay(for: date)
        case .weekly(let weekday):
            return Cycle.weeklyPeriodStart(matches: weekday, of: date)
        case .monthly(let anchor):
            return Cycle.monthlyPeriodStart(matches: anchor, of: date)
        }
    }

    /// Exclusive end of the budget period of `date` (i.e. next period start).
    func end(of: Date = CommitmentScheduling.now()) -> Date {
        let cal = CommitmentScheduling.calendar
        let start = start(of: of)
        switch self {
        case .daily: return cal.date(byAdding: .day, value: 1, to: start) ?? start
        case .weekly: return cal.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
        case .monthly(let day): return Cycle.nextMonthlyPeriodStart(anchorDay: day, after: start)
        }
    }

    // MARK: - Private: Anchor-based period math

    /// Most recent date on or before `date` whose weekday matches `anchorWeekday` (1 = Sun … 7 = Sat).
    private static func weeklyPeriodStart(matches anchorWeekday: Int, of date: Date) -> Date {
        let cal = CommitmentScheduling.calendar
        let currWeekday = cal.component(.weekday, from: cal.startOfDay(for: date))
        let daysBack = (currWeekday - anchorWeekday + 7) % 7
        return cal.date(byAdding: .day, value: -daysBack, to: cal.startOfDay(for: date))
            ?? cal.startOfDay(for: date)
    }

    /// Most recent date on or before `date` whose day-of-month matches `anchorDay` (1–31),
    /// clamped to the last day of the relevant month.
    private static func monthlyPeriodStart(matches anchorDay: Int, of date: Date) -> Date {
        let cal = CommitmentScheduling.calendar
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
    private static func nextMonthlyPeriodStart(anchorDay: Int, after currentPeriodStart: Date)
        -> Date
    {
        let cal = CommitmentScheduling.calendar
        let nextMonth =
            cal.date(byAdding: .month, value: 1, to: currentPeriodStart) ?? currentPeriodStart
        return clampedMonthDay(anchorDay, inMonthOf: nextMonth, cal: cal) ?? nextMonth
    }
}
