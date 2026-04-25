import Foundation
import Testing

@testable import Wilgo

// MARK: - Helpers

/// Returns a Date for the given year/month/day at midnight.
private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = hour
    comps.minute = minute
    comps.second = 0
    return Calendar.current.date(from: comps)!
}

/// A whole-day sentinel: same hour+minute for start and end.
private func wholeDaySlot(recurrence: SlotRecurrence = .everyDay) -> Slot {
    let ref = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: .now)!
    return Slot(start: ref, end: ref, recurrence: recurrence)
}

struct SlotWholeDayTests {

    // MARK: - isWholeDay

    @Test func isWholeDay_whenStartEqualsEnd_returnsTrue() {
        let cal = Calendar.current
        // midnight
        let midnight = cal.date(bySettingHour: 0, minute: 0, second: 0, of: .now)!
        let slot1 = Slot(start: midnight, end: midnight)
        #expect(slot1.isWholeDay == true)
        // non-midnight (9:30 == 9:30)
        let nineThirty = cal.date(bySettingHour: 9, minute: 30, second: 0, of: .now)!
        let slot2 = Slot(start: nineThirty, end: nineThirty)
        #expect(slot2.isWholeDay == true)
    }

    @Test func isWholeDay_whenStartDiffersFromEnd_returnsFalse() {
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
        let end = cal.date(bySettingHour: 10, minute: 0, second: 0, of: .now)!
        let slot = Slot(start: start, end: end)
        #expect(slot.isWholeDay == false)
    }

    // MARK: - timeOfDayText

    @Test func timeOfDayText_wholeDaySlot_containsWholeDayPrefix() {
        let ref = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
        let slot = Slot(start: ref, end: ref)
        #expect(slot.timeOfDayText.hasPrefix("Whole day (from "))
    }

    @Test func timeOfDayText_normalSlot_returnsTimeRange() {
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
        let end = cal.date(bySettingHour: 10, minute: 0, second: 0, of: .now)!
        let slot = Slot(start: start, end: end)
        #expect(slot.timeOfDayText != "Whole day")
        #expect(slot.timeOfDayText.contains("–"))
    }
}
