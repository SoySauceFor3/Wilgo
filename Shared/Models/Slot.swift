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

    /// Returns true when start and end represent the same time-of-day,
    /// which is the sentinel for "active the whole day".
    /// The existing `contains(timeOfDay:)` midnight-crossing branch already
    /// returns `true` for all times in this case.
    var isWholeDay: Bool {
        let calendar = Calendar.current
        let s = calendar.dateComponents([.hour, .minute], from: start)
        let e = calendar.dateComponents([.hour, .minute], from: end)
        return (s.hour ?? 0) == (e.hour ?? 0) && (s.minute ?? 0) == (e.minute ?? 0)
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

    /// Returns true if the given date's time-of-day falls within this slot's window.
    /// timeOfDay: only considers the hour and minute.
    func contains(timeOfDay: Date) -> Bool {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: timeOfDay)
        let startComponents = calendar.dateComponents([.hour, .minute], from: start)
        let endComponents = calendar.dateComponents([.hour, .minute], from: end)

        let timeMinutes = (timeComponents.hour ?? 0) * 60 + (timeComponents.minute ?? 0)
        let startMinutes = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
        let endMinutes = (endComponents.hour ?? 0) * 60 + (endComponents.minute ?? 0)

        if startMinutes < endMinutes {
            // Window does not cross midnight.
            return startMinutes <= timeMinutes && timeMinutes <= endMinutes
        } else {
            // Window crosses midnight.
            return timeMinutes >= startMinutes || timeMinutes <= endMinutes
        }
    }

    /// Fraction of the window remaining at the given date's time-of-day.
    /// Assumes `time` lies within the slot's window.
    func remainingFraction(at timeOfDay: Date) -> Double {
        precondition(
            contains(timeOfDay: timeOfDay),
            "timeOfDay is not within the slot's window"
        )
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: timeOfDay)
        let startComponents = calendar.dateComponents([.hour, .minute], from: start)
        let endComponents = calendar.dateComponents([.hour, .minute], from: end)

        let timeMinutes = (timeComponents.hour ?? 0) * 60 + (timeComponents.minute ?? 0)
        let startMinutes = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
        let endMinutes = (endComponents.hour ?? 0) * 60 + (endComponents.minute ?? 0)

        let remaining: Double
        let duration: Double

        if startMinutes < endMinutes {
            remaining = Double(endMinutes - timeMinutes)
            duration = Double(endMinutes - startMinutes)
        } else {
            let minutesInDay = 24 * 60
            remaining = Double(
                (endMinutes >= timeMinutes
                    ? endMinutes - timeMinutes
                    : minutesInDay - timeMinutes + endMinutes))
            duration = Double(minutesInDay - startMinutes + endMinutes)
        }

        return remaining / duration
    }

    /// Returns true if, at the given **calendar** time, this slot is both
    /// within its start–end window and active according to its recurrence rule.
    ///
    /// This deliberately ignores psychDay offsets. For example, if the user sets their
    /// day-start offset to noon, a slot configured for "Monday 00:00–01:00" is still
    /// considered to belong to **calendar Monday**, not Tuesday.
    func isActive(on time: Date, calendar: Calendar = Time.calendar) -> Bool {
        // First ensure the time-of-day lies within this slot's window.
        guard contains(timeOfDay: time) else { return false }
        // Determine the "anchor" calendar date that this occurrence belongs to.
        // For windows that cross midnight (e.g. 23:00–01:00), times between midnight
        // and the end-of-window are attributed back to the *start* day.
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        let startComponents = calendar.dateComponents([.hour, .minute], from: start)
        let endComponents = calendar.dateComponents([.hour, .minute], from: end)
        let timeMinutes = (timeComponents.hour ?? 0) * 60 + (timeComponents.minute ?? 0)
        let startMinutes = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
        let endMinutes = (endComponents.hour ?? 0) * 60 + (endComponents.minute ?? 0)

        let anchorDate: Date
        if startMinutes < endMinutes {
            // Does not cross midnight: use the calendar day of `time` directly.
            anchorDate = time
        } else {
            // Crosses midnight:
            //  - times >= startMinutes are on the start day
            //  - times < startMinutes (i.e. after midnight) belong to the previous calendar day
            if timeMinutes >= startMinutes {
                anchorDate = time
            } else {
                anchorDate = calendar.date(byAdding: .day, value: -1, to: time) ?? time
            }
        }

        switch recurrence {
        case .everyDay:
            return true

        case .specificWeekdays(let weekdays):
            let weekday = calendar.component(.weekday, from: anchorDate)  // 1 = Sunday … 7 = Saturday
            return weekdays.contains(weekday)

        case .specificMonthDays(let days):
            let day = calendar.component(.day, from: anchorDate)
            return days.contains(day)
        }
    }
}

extension Slot {
    /// Returns true if this slot's occurrence on the psychDay of `time` has been snoozed.
    /// Returns false if `time` is outside this slot's active window (no active occurrence → not snoozed).
    func isSnoozed(at time: Date, calendar: Calendar = Time.calendar) -> Bool {
        guard self.isActive(on: time, calendar: calendar) else {
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
