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
        case .specificWeekdays(let weekdays):
            return !weekdays.isEmpty
        case .specificMonthDays(let days):
            return !days.isEmpty
        }
    }

    /// Returns true if this recurrence rule matches the given calendar date.
    /// Only the date's calendar day matters — the time-of-day component is ignored.
    func matches(date: Date, calendar: Calendar) -> Bool {
        switch self {
        case .everyDay:
            return true
        case .specificWeekdays(let weekdays):
            let weekday = calendar.component(.weekday, from: date)
            return weekdays.contains(weekday)
        case .specificMonthDays(let days):
            let day = calendar.component(.day, from: date)
            return days.contains(day)
        }
    }

    var summaryText: String {
        let calendar = Calendar.current
        switch self {
        case .everyDay:
            return "Every day"
        case .specificWeekdays(let weekdays):
            let symbols = calendar.shortWeekdaySymbols  // Sunday-first (localized)
            let ordered = (1...7).filter { weekdays.contains($0) }
            if ordered.count == 7 { return "Every day" }
            if ordered.isEmpty { return "" }
            let parts = ordered.map { String(symbols[$0 - 1].prefix(3)) }
            return parts.joined(separator: ", ")
        case .specificMonthDays(let days):
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
    var maxCheckIns: Int? = nil

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
        recurrence: SlotRecurrence = .everyDay
    ) {
        self.id = UUID()
        self.start = start
        self.end = end
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

            case .specificWeekdays(let weekdays):
                recurrenceKindRaw = RecurrenceKind.specificWeekdays.rawValue
                activeWeekdays = Array(weekdays).sorted()
                activeMonthDays = []

            case .specificMonthDays(let days):
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
    private func anchorDate(for time: Date, calendar: Calendar) -> Date {
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

    /// Resolves this slot's time-of-day window into concrete datetimes on the given psych day.
    /// Returns `nil` if the slot's recurrence rule excludes this day.
    /// The returned `Slot` carries the original slot's `id` so callers can look up the
    /// persisted Slot in the SwiftData store.
    func resolveOccurrence(on psychDay: Date, calendar: Calendar = Time.calendar) -> Slot? {
        guard self.recurrence.matches(date: psychDay, calendar: calendar) else { return nil }

        let start = Time.resolve(timeOfDay: self.start, on: psychDay)
        var end = Time.resolve(timeOfDay: self.end, on: psychDay)
        if end <= start {
            end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        }

        // For slots with selected days
        guard isScheduled(on: start, calendar: calendar) else { return nil }

        let resolved = Slot(start: start, end: end)
        resolved.id = self.id
        return resolved
    }
}

extension Slot {
    /// Returns true if this slot's occurrence on the psychDay of `time` has been snoozed.
    /// Returns false if `time` is outside this slot's scheduled window (no occurrence → not snoozed).
    func isSnoozed(at time: Date, calendar: Calendar = Time.calendar) -> Bool {
        guard self.isScheduled(on: time, calendar: calendar) else {
            return false
        }

        guard let psychDay = try? SlotSnooze.slotPsychDay(slot: self, at: time, calendar: calendar)
        else {
            return false
        }

        return snoozes.contains { snooze in
            calendar.isDate(snooze.psychDay, inSameDayAs: psychDay)
        }
    }
}

// MARK: - Capacity

extension Slot {
    /// Returns true if this slot's occurrence on the psych-day of `time`
    /// has been saturated by check-ins whose `createdAt` falls in
    /// `[occurrence.start, occurrence.end)`.
    ///
    /// Returns false if:
    /// - `maxCheckIns` is nil (unlimited), or
    /// - `time` is outside this slot's scheduled window (no occurrence to saturate).
    func isSaturated(
        at time: Date,
        checkIns: [CheckIn],
        calendar: Calendar = Time.calendar
    ) -> Bool {
        guard let cap = maxCheckIns, cap > 0 else { return false }
        guard self.isScheduled(on: time, calendar: calendar) else { return false }

        // Resolve the occurrence anchored on `time`'s psych-day in order to
        // get concrete [start, end) datetimes. Use the same anchorDate logic
        // implicit in resolveOccurrence by walking from the calendar day of `time`.
        let psychDay = calendar.startOfDay(for: time)
        guard let occurrence = self.resolveOccurrence(on: psychDay, calendar: calendar) else {
            return false
        }
        return Self.countCheckInsInWindow(
            checkIns: checkIns,
            start: occurrence.start,
            end: occurrence.end
        ) >= cap
    }

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
