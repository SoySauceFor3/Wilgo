import Testing
import Foundation
@testable import Wilgo

struct SlotWholeDayTests {

    // MARK: - isWholeDay

    @Test func isWholeDay_whenStartEqualsEnd_returnsTrue() {
        let ref = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: .now)!
        let slot = Slot(start: ref, end: ref)
        #expect(slot.isWholeDay == true)
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

        let times: [Int] = [0, 3, 9, 12, 17, 23]
        for hour in times {
            let t = cal.date(bySettingHour: hour, minute: 30, second: 0, of: .now)!
            #expect(slot.contains(timeOfDay: t), "Expected whole-day slot to contain hour \(hour)")
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
