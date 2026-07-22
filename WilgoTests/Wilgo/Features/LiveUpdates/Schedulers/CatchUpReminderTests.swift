import Foundation
import Testing
@testable import Wilgo

extension LiveUpdatesSuite.SchedulersSuite {
@Suite(.serialized)
final class CatchUpReminderTests {
    // MARK: - Helpers

    private func date(
        year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0
    ) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        c.minute = minute
        c.second = 0
        return Calendar.current.date(from: c)!
    }

    // MARK: - catchUpOffsetHours shape

    @Test("offset sequence has exactly 10 entries")
    func offsetSequence_hasTenEntries() {
        #expect(CatchUpReminder.catchUpOffsetHours.count == 10)
    }

    @Test("offset sequence is strictly increasing")
    func offsetSequence_isStrictlyIncreasing() {
        let offsets = CatchUpReminder.catchUpOffsetHours
        for i in 1..<offsets.count {
            #expect(offsets[i] > offsets[i - 1])
        }
    }

    @Test("first offset is 1 hour")
    func offsetSequence_firstIsOneHour() {
        #expect(CatchUpReminder.catchUpOffsetHours.first == 1)
    }

    @Test("last offset is 672 hours (4 weeks)")
    func offsetSequence_lastIsFourWeeks() {
        #expect(CatchUpReminder.catchUpOffsetHours.last == 672)
    }

    @Test("offset count matches maxPendingCount")
    func offsetSequence_countMatchesMaxPendingCount() {
        #expect(CatchUpReminder.catchUpOffsetHours.count == CatchUpReminder.maxPendingCount)
    }

    // MARK: - fireDates(from:now:)

    @Test("all offsets in the future are returned when anchor == now")
    func fireDates_allFuture_whenAnchorEqualsNow() {
        let anchor = date(year: 2026, month: 1, day: 1, hour: 0)
        let now = anchor

        let result = CatchUpReminder.fireDates(from: anchor, now: now)

        // All 10 offsets are > 0, so all produce dates > now
        #expect(result.count == CatchUpReminder.maxPendingCount)
    }

    @Test("dates in the past are excluded")
    func fireDates_pastDatesExcluded() {
        let anchor = date(year: 2026, month: 1, day: 1, hour: 0)
        // now is 3 hours after anchor — offsets 1h and 3h are in the past
        let now = date(year: 2026, month: 1, day: 1, hour: 3)

        let result = CatchUpReminder.fireDates(from: anchor, now: now)

        // offsets 1h, 3h produce dates <= now → excluded; first included: 7h
        #expect(result.first == anchor.addingTimeInterval(7 * 3600))
    }

    @Test("returns empty when all offsets are in the past")
    func fireDates_allPast_returnsEmpty() {
        let anchor = date(year: 2026, month: 1, day: 1, hour: 0)
        // now is beyond the last offset (672h = 28 days)
        let now = date(year: 2026, month: 3, day: 1)

        let result = CatchUpReminder.fireDates(from: anchor, now: now)

        #expect(result.isEmpty)
    }

    @Test("each returned date corresponds to the correct offset from anchor")
    func fireDates_datesMatchOffsets() {
        let anchor = date(year: 2026, month: 1, day: 1, hour: 0)
        let now = date(year: 2025, month: 12, day: 31)  // all offsets in future

        let result = CatchUpReminder.fireDates(from: anchor, now: now)

        for (resultDate, offset) in zip(result, CatchUpReminder.catchUpOffsetHours) {
            let expected = anchor.addingTimeInterval(offset * 3600)
            #expect(resultDate == expected)
        }
    }

    // MARK: - AppSettings gate

    /// `performWork()` gates all scheduling on `AppSettings.catchUpRemindersEnabled` before it
    /// ever touches `UNUserNotificationCenter`, so it cannot be exercised end-to-end without
    /// mocking the system notification center (disallowed). The testable seam is the gate
    /// condition itself: confirms the toggle the scheduler reads defaults to enabled and
    /// correctly reports disabled when the user has opted out, which is what `performWork()`
    /// branches on.
    private func withStored(_ key: String, _ value: Bool?, _ body: () -> Void) {
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        body()
    }

    @Test("performWork's gate: catchUpRemindersEnabled defaults to true (no opt-out)")
    func gate_defaultsToEnabled() {
        withStored(AppSettings.catchUpRemindersEnabledKey, nil) {
            #expect(AppSettings.catchUpRemindersEnabled == true)
        }
    }

    @Test("performWork's gate: catchUpRemindersEnabled false when user disables the toggle")
    func gate_disabledWhenToggledOff() {
        withStored(AppSettings.catchUpRemindersEnabledKey, false) {
            #expect(AppSettings.catchUpRemindersEnabled == false)
        }
    }
}
}
