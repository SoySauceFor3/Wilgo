import Foundation
import SwiftData

enum SlotRecurrence: Codable, Hashable {
    /// Active every calendar day.
    case everyDay
    /// Active only on specific weekdays (1 = Sunday … 7 = Saturday, `Calendar.current.weekday`).
    case specificWeekdays(Set<Int>)
    /// Active only on specific month days (1 … 31).
    case specificMonthDays(Set<Int>)

    var isValidSelection: Bool {
        switch self {
        case .everyDay:
            return true
        case let .specificWeekdays(weekdays):
            return !weekdays.isEmpty
        case let .specificMonthDays(days):
            return !days.isEmpty
        }
    }

    /// Returns true if this recurrence rule matches the given calendar date.
    /// Only the date's calendar day matters — the time-of-day component is ignored.
    func matches(date: Date, calendar: Calendar) -> Bool {
        switch self {
        case .everyDay:
            return true
        case let .specificWeekdays(weekdays):
            let weekday = calendar.component(.weekday, from: date)
            return weekdays.contains(weekday)
        case let .specificMonthDays(days):
            let day = calendar.component(.day, from: date)
            return days.contains(day)
        }
    }

    /// The next start-of-day on or after `day` that this recurrence matches, or `nil` if it can
    /// never match (e.g. an empty weekday/month-day set). Computed from each kind's own period,
    /// so there is no external "lookahead days" constant: adding a new recurrence kind defines
    /// its own search here and stays correct for arbitrary periods.
    func nextMatchDay(onOrAfter day: Date, calendar: Calendar = Time.calendar) -> Date? {
        let start = calendar.startOfDay(for: day)
        switch self {
        case .everyDay:
            return start
        case let .specificWeekdays(weekdays):
            guard !weekdays.isEmpty else { return nil }
            // A weekly pattern repeats within 7 days; the first match must occur in [0, 7).
            return firstDay(from: start, within: 7, calendar: calendar)
        case let .specificMonthDays(days):
            guard !days.isEmpty else { return nil }
            // A month-day pattern repeats within a month; two months covers any gap
            // (e.g. day 31 skipping a short month).
            return firstDay(from: start, within: 62, calendar: calendar)
        }
    }

    /// Steps forward day-by-day from `start` (inclusive) up to `limit` days, returning the first
    /// that `matches`. Private so the per-kind `limit` (an intrinsic property of that kind, not a
    /// shared magic number) stays co-located with `nextMatchDay`.
    /// start: expect start of day, but works fine with day+time
    private func firstDay(from start: Date, within limit: Int, calendar: Calendar = Time.calendar)
        -> Date?
    {
        var cursor = start
        for _ in 0..<limit {
            if matches(date: cursor, calendar: calendar) { return cursor }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            cursor = next
        }
        return nil
    }

    var summaryText: String {
        let calendar = Calendar.current
        switch self {
        case .everyDay:
            return "Every day"
        case let .specificWeekdays(weekdays):
            let symbols = calendar.shortWeekdaySymbols  // Sunday-first (localized)
            let ordered = (1...7).filter { weekdays.contains($0) }
            if ordered.count == 7 { return "Every day" }
            if ordered.isEmpty { return "" }
            let parts = ordered.map { String(symbols[$0 - 1].prefix(3)) }
            return parts.joined(separator: ", ")
        case let .specificMonthDays(days):
            let ordered = days.sorted()
            if ordered.isEmpty { return "" }
            let joined = ordered.map(String.init).joined(separator: ", ")
            return "day \(joined) every month"
        }
    }
}

@Model
final class Slot {
    @Attribute(.unique)
    var id: UUID
    /// Start of this slot's ideal window (time-of-day only, arbitrary reference day).
    var start: Date
    /// End of this slot's ideal window (time-of-day only).
    var end: Date

    /// Optional cap on how many check-ins inside one resolved occurrence's window
    /// can satisfy this slot. `nil` = unlimited (default).
    ///
    /// Capacity is per-occurrence: a recurring slot's Monday occurrence and
    /// Tuesday occurrence each have their own cap.
    ///
    /// Forward-compat: a future `SlotCapacityGroup` entity (Path 2) will hold its
    /// own `maxCheckIns` for cross-slot capacity. The two fields will coexist;
    /// when a slot has a group, the group's cap supersedes this one.
    var maxCheckIns: Int?

    // MARK: - Recurrence backing storage (SwiftData-friendly)

    private enum RecurrenceKind: String, Codable {
        case everyDay
        case specificWeekdays
        case specificMonthDays
    }

    /// Stored as a raw kind + payload arrays that are friendly to SwiftData.
    private var recurrenceKindRaw: String = RecurrenceKind.everyDay.rawValue
    private var activeWeekdays: [Int] = []
    private var activeMonthDays: [Int] = []

    @Relationship var commitment: Commitment?

    /// Snoozes applied to this slot. Cascade: deleting this slot deletes its snoozes.
    @Relationship(deleteRule: .cascade, inverse: \SlotSnooze.slot)
    var snoozes: [SlotSnooze] = []

    init(
        start: Date,
        end: Date,
        recurrence: SlotRecurrence = .everyDay,
        maxCheckIns: Int? = nil
    ) {
        self.id = UUID()
        self.start = start
        self.end = end
        self.maxCheckIns = maxCheckIns
        self.recurrence = recurrence
    }
}

// MARK: - High-level recurrence API

extension Slot {
    /// High-level recurrence API backed by primitive storage.
    var recurrence: SlotRecurrence {
        get {
            let kind = RecurrenceKind(rawValue: recurrenceKindRaw) ?? .everyDay
            switch kind {
            case .everyDay:
                return .everyDay
            case .specificWeekdays:
                return .specificWeekdays(Set(activeWeekdays))
            case .specificMonthDays:
                return .specificMonthDays(Set(activeMonthDays))
            }
        }
        set {
            switch newValue {
            case .everyDay:
                recurrenceKindRaw = RecurrenceKind.everyDay.rawValue
                activeWeekdays = []
                activeMonthDays = []

            case let .specificWeekdays(weekdays):
                recurrenceKindRaw = RecurrenceKind.specificWeekdays.rawValue
                activeWeekdays = Array(weekdays).sorted()
                activeMonthDays = []

            case let .specificMonthDays(days):
                recurrenceKindRaw = RecurrenceKind.specificMonthDays.rawValue
                activeMonthDays = Array(days).sorted()
                activeWeekdays = []
            }
        }
    }
}

extension Slot {
    /// Start of the slot mapped onto the current psychological day.
    var startToday: Date { Time.resolve(timeOfDay: start) }

    /// End of the slot mapped onto the current psychological day.
    var endToday: Date { Time.resolve(timeOfDay: end) }

    /// Absolute end datetime of the occurrence that *starts* on `day`.
    ///
    /// For a normal window the end falls on `day` itself. For a cross-midnight
    /// window (e.g. 23:00–01:00) the end falls on the following calendar day.
    /// Pass the psychDay the slot *starts* on, not the day it ends.
    func endTime(onDayStarting day: Date, calendar: Calendar = Time.calendar) -> Date {
        var end = Time.resolve(timeOfDay: self.end, on: day)
        if crossesMidnight {
            end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        }
        return end
    }

    var timeOfDayText: String {
        if isWholeDay {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return "Whole day (from \(formatter.string(from: start)))"
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    var label: String {
        let recurrenceText = recurrence.summaryText
        if recurrenceText.isEmpty {
            return timeOfDayText
        }
        return "\(timeOfDayText) on \(recurrenceText)"
    }

    /// Minutes elapsed since midnight for the time-of-day component of `date`.
    private func minutesSinceMidnight(of date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Returns true when start and end represent the same time-of-day,
    /// which is the sentinel for "active the whole day".
    var isWholeDay: Bool {
        minutesSinceMidnight(of: start) == minutesSinceMidnight(of: end)
    }

    /// Whether this slot's time window crosses midnight (e.g. 23:00–01:00).
    var crossesMidnight: Bool { minutesSinceMidnight(of: start) >= minutesSinceMidnight(of: end) }

    /// Returns true if the given date's time-of-day falls within this slot's window.
    /// Pure time-of-day check — does not consider recurrence or snooze.
    private func containsTime(_ timeOfDay: Date) -> Bool {
        let t = minutesSinceMidnight(of: timeOfDay)
        let s = minutesSinceMidnight(of: start)
        let e = minutesSinceMidnight(of: end)
        return crossesMidnight ? (t >= s || t <= e) : (t >= s && t <= e)
    }

    /// Fraction of the window remaining at `time`.
    /// Precondition: `dateTime` must satisfy `isScheduled(on:)` — i.e. within the window and on a scheduled day.
    func remainingFraction(at dateTime: Date, calendar: Calendar = Time.calendar) -> Double {
        precondition(
            isScheduled(on: dateTime, calendar: calendar),
            "time is not within the slot's scheduled window")
        let t = minutesSinceMidnight(of: dateTime)
        let s = minutesSinceMidnight(of: start)
        let e = minutesSinceMidnight(of: end)
        if !crossesMidnight {
            return Double(e - t) / Double(e - s)
        }
        let minutesInDay = 24 * 60
        let duration = minutesInDay - s + e
        let remaining = e >= t ? e - t : minutesInDay - t + e
        return Double(remaining) / Double(duration)
    }

    /// The calendar day (at 00:00) this occurrence "belongs to".
    /// For cross-midnight windows (e.g. 23:00–01:00), post-midnight times are
    /// attributed back to the previous calendar day (the day the window started).
    /// Precondition: `time` must be within this slot's window (`containsTime` is true).
    func anchorDate(for time: Date, calendar: Calendar = Time.calendar) -> Date {
        guard containsTime(time) else {
            assertionFailure("anchorDate(for:) called with time outside slot window")
            return calendar.startOfDay(for: time)
        }
        guard crossesMidnight else { return calendar.startOfDay(for: time) }
        if minutesSinceMidnight(of: time) >= minutesSinceMidnight(of: start) {
            // Pre-midnight portion: belongs to the current calendar day.
            return calendar.startOfDay(for: time)
        }
        // Post-midnight portion: belongs to the previous calendar day.
        let yesterday = calendar.date(byAdding: .day, value: -1, to: time) ?? time
        return calendar.startOfDay(for: yesterday)
    }

    /// Returns true if, at the given **calendar** time, this slot is both
    /// within its start–end window and scheduled according to its recurrence rule.
    /// Does not consider snooze state.
    func isScheduled(on time: Date, calendar: Calendar = Time.calendar) -> Bool {
        guard containsTime(time) else { return false }
        let anchor = anchorDate(for: time, calendar: calendar)
        return recurrence.matches(date: anchor, calendar: calendar)
    }

    /// Resolves this slot's firing on `psychDay` as a `SlotOccurrence`, or `nil` if the
    /// slot's recurrence excludes that day.
    ///
    /// This is the only constructor of `SlotOccurrence`: a firing for a day the slot does
    /// not fire cannot be built.
    func occurrence(on psychDay: Date, calendar: Calendar = Time.calendar) -> SlotOccurrence? {
        guard recurrence.matches(date: psychDay, calendar: calendar) else { return nil }
        return SlotOccurrence(slot: self, psychDay: psychDay)
    }

    /// This slot's next occurrence whose `start >= instant`, or `nil` if the recurrence never
    /// matches. Pure scheduling — ignores snooze and saturation.
    ///
    /// Jumps via `recurrence.nextMatchDay`, so it never scans irrelevant days. Handles the boundary
    /// case where the next *matching day* is `instant`'s own day but that day's occurrence already
    /// started (e.g. `instant` is 11 PM, the slot fires at 7 AM): it advances to the following
    /// match. At most one such advance is ever needed, so this terminates in O(1) match lookups.
    func nextOccurrence(onOrAfter instant: Date, calendar: Calendar = Time.calendar)
        -> SlotOccurrence?
    {
        var dayCursor = calendar.startOfDay(for: instant)
        // Two iterations suffice: the first match-day may yield an already-started occurrence;
        // the next match-day's occurrence necessarily starts later.
        for _ in 0..<2 {
            guard let matchDay = recurrence.nextMatchDay(onOrAfter: dayCursor, calendar: calendar),
                let occ = occurrence(on: matchDay, calendar: calendar)
            else { return nil }
            if occ.start >= instant { return occ }
            guard let next = calendar.date(byAdding: .day, value: 1, to: matchDay) else {
                return nil
            }
            dayCursor = next
        }
        return nil
    }

    /// This slot's occurrences overlapping the half-open datetime window `[from, until)`, in day
    /// order. Pure scheduling — ignores snooze and saturation (those are usability, evaluated by the
    /// owning commitment against its check-ins).
    ///
    /// `softFrom` / `softUntil` say whether each window edge is "soft" — whether an occurrence may
    /// cross it:
    /// - `softFrom`: allow occurrences starting before `from` (`occ.start < from`) — the
    ///   cross-midnight carry-overs from the prior day.
    /// - `softUntil`: allow occurrences ending past `until` (`occ.end > until`). `end == until` does
    ///   NOT cross — `end` is exclusive, so such an occurrence is fully inside and never gated here.
    /// An occurrence covering the whole window crosses both edges, so it needs `softFrom && softUntil`.
    ///
    /// The day-walk starts one day before `from`'s day so a cross-midnight occurrence anchored on the
    /// prior day (its tail in the window) is enumerated.
    func occurrences(
        from: Date,
        until: Date,
        softFrom: Bool = true,
        softUntil: Bool = true,
        calendar: Calendar = Time.calendar
    ) -> [SlotOccurrence] {
        var occurrences: [SlotOccurrence] = []

        let firstDay =
            calendar.date(byAdding: .day, value: -1, to: Time.startOfDay(for: from))
            ?? Time.startOfDay(for: from)
        var dayCursor = firstDay
        while dayCursor < until {
            defer { dayCursor = calendar.date(byAdding: .day, value: 1, to: dayCursor) ?? until }

            guard let occurrence = occurrence(on: dayCursor, calendar: calendar) else { continue }
            // Overlap test against the datetime window.
            guard occurrence.start < until, occurrence.end > from else { continue }
            if occurrence.start < from, !softFrom { continue }
            if occurrence.end > until, !softUntil { continue }

            occurrences.append(occurrence)
        }
        return occurrences
    }
}

// MARK: - Snooze

extension Slot {
    /// Snoozes this slot's firing at `time`, inserting a `SlotSnooze`, or returns `nil` if
    /// `time` is outside the slot's active window (wrong time-of-day or wrong recurrence day).
    ///
    /// Always clears **all** of this slot's existing snoozes first (even when this returns `nil`).
    /// This is safe and simpler than selective stale-cleanup because a slot fires at most once per
    /// logical day and `snooze(at:)` is only ever called for the *current* firing — so any existing
    /// snooze is necessarily for an earlier day, or today's (which we are replacing). Clearing all
    /// also guarantees a slot never accumulates duplicate snoozes for the same day.
    /// (Assumption: no caller pre-snoozes a *future* firing; if that ever changes, this must too.)
    ///
    /// The recorded `psychDay` is the anchor day of the firing containing `time` (frozen here,
    /// never re-derived on read). For cross-midnight slots (e.g. 11pm–1am), a snooze tapped at
    /// 12am Jan 1 belongs to the Dec 31 firing, so `psychDay = Dec 31`.
    ///
    /// - Parameters:
    ///   - time: The creation time (injectable for testing), and effective time.
    ///   - context: The SwiftData context to insert into. `@Model` objects require an explicit
    ///     `ModelContext` for insert/delete — there is no implicit context on the model itself.
    /// - Returns: The newly created `SlotSnooze`, or `nil` if `time` is not in the slot's window.
    @discardableResult
    func snooze(
        at time: Date = Time.now(), in context: ModelContext, calendar: Calendar = Time.calendar
    ) -> SlotSnooze? {
        // Clear all existing snoozes — see doc: any prior snooze is for a past day (or today's,
        // which we replace), so this can't drop a snooze that's still relevant.
        for s in snoozes {
            context.delete(s)
        }
        snoozes.removeAll()

        guard isScheduled(on: time, calendar: calendar) else { return nil }

        let psychDay = anchorDate(for: time, calendar: calendar)
        let snooze = SlotSnooze(slot: self, psychDay: psychDay, snoozedAt: time)
        context.insert(snooze)
        return snooze
    }
}

// MARK: - Capacity

extension Slot {
    /// Pure helper: how many check-ins fall in `[start, end)` by `createdAt`.
    static func countCheckInsInWindow(
        checkIns: [CheckIn],
        start: Date,
        end: Date
    ) -> Int {
        checkIns.reduce(0) { acc, checkIn in
            (checkIn.createdAt >= start && checkIn.createdAt < end) ? acc + 1 : acc
        }
    }
}

extension Slot: Comparable {
    static func < (lhs: Slot, rhs: Slot) -> Bool {
        if lhs.start == rhs.start {
            return lhs.endToday < rhs.endToday
        } else {
            return lhs.startToday < rhs.startToday
        }
    }

    static func == (lhs: Slot, rhs: Slot) -> Bool {
        lhs.start == rhs.start && lhs.end == rhs.end
    }
}
