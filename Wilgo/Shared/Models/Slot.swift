import Foundation
import SwiftData

@Model
final class Slot {
    /// Start of this slot's ideal window (time-of-day only, arbitrary reference day).
    var start: Date
    /// End of this slot's ideal window (time-of-day only).
    var end: Date

    @Relationship var habit: Habit?

    init(
        start: Date,
        end: Date
    ) {
        self.start = start
        self.end = end
    }
}

extension Slot {
    /// Start of the slot mapped onto the current psychological day.
    var startToday: Date { HabitScheduling.resolve(timeOfDay: start) }

    /// End of the slot mapped onto the current psychological day.
    var endToday: Date { HabitScheduling.resolve(timeOfDay: end) }

    var slotTimeText: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
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
