import Testing
import Foundation
@testable import Wilgo

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
        let end   = cal.date(bySettingHour: 10, minute: 0, second: 0, of: .now)!
        let slot = Slot(start: start, end: end)
        #expect(slot.isWholeDay == false)
    }

    // MARK: - contains (whole day)

    @Test func contains_wholeDaySlot_returnsTrueForAnyTime() throws {
        let cal = Calendar.current
        let ref = cal.date(bySettingHour: 0, minute: 0, second: 0, of: .now)!
        let slot = Slot(start: ref, end: ref)

        // spot-check across the day including the exact sentinel value
        let testCases: [(hour: Int, minute: Int)] = [
            (0, 0), (0, 30), (3, 0), (9, 0), (12, 30), (17, 0), (23, 59)
        ]
        for tc in testCases {
            let t = cal.date(bySettingHour: tc.hour, minute: tc.minute, second: 0, of: .now)!
            #expect(slot.contains(timeOfDay: t), "Expected whole-day slot to contain \(tc.hour):\(tc.minute)")
        }
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
        let end   = cal.date(bySettingHour: 10, minute: 0, second: 0, of: .now)!
        let slot = Slot(start: start, end: end)
        #expect(slot.timeOfDayText != "Whole day")
        #expect(slot.timeOfDayText.contains("–"))
    }
}
