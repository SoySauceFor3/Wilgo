import Foundation
import Testing
@testable import Wilgo

// MARK: - Helpers
/// A whole-day sentinel: same hour+minute for start and end.
private func wholeDaySlot(recurrence: SlotRecurrence = .everyDay) -> Slot {
    let ref = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: .now)!
    return Slot(start: ref, end: ref, recurrence: recurrence)
}

extension SlotSuite {
struct SlotWholeDayTests {
    // MARK: - isWholeDay

    @Test func isWholeDay_whenStartEqualsEnd_returnsTrue() throws {
        let cal = Calendar.current
        // midnight
        let midnight = try #require(cal.date(bySettingHour: 0, minute: 0, second: 0, of: .now))
        let slot1 = Slot(start: midnight, end: midnight)
        #expect(slot1.isWholeDay == true)
        // non-midnight (9:30 == 9:30)
        let nineThirty = try #require(cal.date(bySettingHour: 9, minute: 30, second: 0, of: .now))
        let slot2 = Slot(start: nineThirty, end: nineThirty)
        #expect(slot2.isWholeDay == true)
    }

    @Test func isWholeDay_whenStartDiffersFromEnd_returnsFalse() throws {
        let cal = Calendar.current
        let start = try #require(cal.date(bySettingHour: 9, minute: 0, second: 0, of: .now))
        let end = try #require(cal.date(bySettingHour: 10, minute: 0, second: 0, of: .now))
        let slot = Slot(start: start, end: end)
        #expect(slot.isWholeDay == false)
    }

    // MARK: - timeOfDayText

    @Test func timeOfDayText_wholeDaySlot_containsWholeDayPrefix() throws {
        let ref = try #require(Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now))
        let slot = Slot(start: ref, end: ref)
        #expect(slot.timeOfDayText.hasPrefix("Whole day (from "))
    }

    @Test func timeOfDayText_normalSlot_returnsTimeRange() throws {
        let cal = Calendar.current
        let start = try #require(cal.date(bySettingHour: 9, minute: 0, second: 0, of: .now))
        let end = try #require(cal.date(bySettingHour: 10, minute: 0, second: 0, of: .now))
        let slot = Slot(start: start, end: end)
        #expect(slot.timeOfDayText != "Whole day")
        #expect(slot.timeOfDayText.contains("–"))
    }
}
}
