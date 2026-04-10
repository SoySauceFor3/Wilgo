import Foundation
import SwiftData
import Testing

@testable import Wilgo

// MARK: - Helpers

/// Returns a fresh in-memory ModelContainer that includes SlotSnooze.
///
/// IMPORTANT: callers must keep the returned container alive for the entire test.
/// ModelContext only weakly references its container; releasing it will crash.
@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema([Commitment.self, Slot.self, CheckIn.self, SlotSnooze.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

private func timeOfDay(hour: Int, minute: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = 2000
    comps.month = 1
    comps.day = 1
    comps.hour = hour
    comps.minute = minute
    comps.second = 0
    return Calendar.current.date(from: comps)!
}

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

@MainActor
private func makeSlotAndInsert(
    startHour: Int, endHour: Int,
    recurrence: SlotRecurrence = .everyDay,
    in ctx: ModelContext
) -> Slot {
    let anchor = date(year: 2026, month: 1, day: 1)
    let slot = Slot(
        start: timeOfDay(hour: startHour), end: timeOfDay(hour: endHour), recurrence: recurrence)
    let commitment = Commitment(
        title: "Test",
        slots: [slot],
        target: QuantifiedCycle(cycle: Cycle(kind: .daily, referencePsychDay: anchor), count: 1)
    )
    ctx.insert(commitment)
    ctx.insert(slot)
    return slot
}

// MARK: - Tests

@Suite("SlotSnooze.create", .serialized)
struct SlotSnoozeCreateTests: ~Copyable {

    private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)
    init() { UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey) }
    deinit {
        let saved = savedOffset
        UserDefaults.standard.set(saved, forKey: AppSettings.dayStartHourKey)
    }

    // MARK: Happy path

    @Test("create for an active slot → returns a SlotSnooze with correct psychDay")
    @MainActor func create_activeSlot_returnsSnooze() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = makeSlotAndInsert(startHour: 9, endHour: 11, in: ctx)

        let time = date(year: 2026, month: 3, day: 5, hour: 10)  // within 9–11am
        let snooze = SlotSnooze.create(slot: slot, at: time, in: ctx)

        #expect(snooze != nil)
        #expect(slot.snoozes.count == 1)

        let expectedPsychDay = Time.psychDay(for: time)
        #expect(Calendar.current.isDate(snooze!.psychDay, inSameDayAs: expectedPsychDay))
    }

    // MARK: psychDay recording

    @Test("cross-midnight slot: snooze tapped at 12am Jan 1 records psychDay = Dec 31")
    @MainActor func create_crossMidnight_psychDayIsStartDay() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Slot: 11pm–1am (crosses midnight)
        let slot = makeSlotAndInsert(startHour: 23, endHour: 1, in: ctx)

        // Snooze tapped at 12am Jan 1 (post-midnight portion of the Dec 31 slot occurrence)
        let time = date(year: 2026, month: 1, day: 1, hour: 0, minute: 30)
        let snooze = SlotSnooze.create(slot: slot, at: time, in: ctx)

        #expect(snooze != nil)

        // psychDay should be Dec 31, not Jan 1, because the slot started at 11pm Dec 31
        let dec31 = date(year: 2025, month: 12, day: 31)
        #expect(Calendar.current.isDate(snooze!.psychDay, inSameDayAs: dec31))
    }

    @Test("normal slot: snooze records psychDay of time")
    @MainActor func create_normalSlot_psychDayIsToday() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = makeSlotAndInsert(startHour: 9, endHour: 11, in: ctx)

        let time = date(year: 2026, month: 6, day: 15, hour: 10)
        let snooze = SlotSnooze.create(slot: slot, at: time, in: ctx)

        #expect(snooze != nil)
        let expectedPsychDay = date(year: 2026, month: 6, day: 15)
        #expect(Calendar.current.isDate(snooze!.psychDay, inSameDayAs: expectedPsychDay))
    }

    // MARK: Returns nil when outside window

    @Test("create when time is after slot window → returns nil")
    @MainActor func create_afterSlotWindow_returnsNil() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Slot: 1–3am; time is 5am (slot has ended)
        let slot = makeSlotAndInsert(startHour: 1, endHour: 3, in: ctx)
        let time = date(year: 2026, month: 3, day: 5, hour: 5)

        let snooze = SlotSnooze.create(slot: slot, at: time, in: ctx)

        #expect(snooze == nil)
        #expect(slot.snoozes.isEmpty)
    }

    @Test("create when time is before slot window → returns nil")
    @MainActor func create_beforeSlotWindow_returnsNil() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Slot: 9–11am; time is 7am
        let slot = makeSlotAndInsert(startHour: 9, endHour: 11, in: ctx)
        let time = date(year: 2026, month: 3, day: 5, hour: 7)

        let snooze = SlotSnooze.create(slot: slot, at: time, in: ctx)

        #expect(snooze == nil)
        #expect(slot.snoozes.isEmpty)
    }

    @Test("create on wrong recurrence day → returns nil")
    @MainActor func create_wrongRecurrenceDay_returnsNil() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Monday-only slot (weekday 2 in 1=Sun…7=Sat calendar)
        let slot = makeSlotAndInsert(
            startHour: 9, endHour: 11, recurrence: .specificWeekdays([2]), in: ctx)

        // Tuesday Jan 1 2026 (weekday = 5 = Thursday? let's use a ktimen Tuesday)
        // Jan 6 2026 is a Tuesday. Weekday: 1=Sun,2=Mon,3=Tue
        // We need a day that is NOT Monday. Jan 6 2026 = Tuesday.
        let tuesday = date(year: 2026, month: 1, day: 6, hour: 10)  // Tuesday, within time window
        let snooze = SlotSnooze.create(slot: slot, at: tuesday, in: ctx)

        #expect(snooze == nil)
        #expect(slot.snoozes.isEmpty)
    }

    @Test("create on correct recurrence day → returns snooze")
    @MainActor func create_correctRecurrenceDay_returnsSnooze() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Monday-only slot
        let slot = makeSlotAndInsert(
            startHour: 9, endHour: 11, recurrence: .specificWeekdays([2]), in: ctx)

        // Jan 5 2026 is a Monday
        let monday = date(year: 2026, month: 1, day: 5, hour: 10)
        let snooze = SlotSnooze.create(slot: slot, at: monday, in: ctx)

        #expect(snooze != nil)
    }

    // MARK: Stale cleanup

    @Test("stale snooze (resolvedSlotEnd in past) is deleted on next create call")
    @MainActor func create_deletesStaleSnooze() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Slot: 9–11am
        let slot = makeSlotAndInsert(startHour: 9, endHour: 11, in: ctx)

        // Insert a stale snooze for yesterday
        let yesterday = date(year: 2026, month: 3, day: 4)
        let stale = SlotSnooze(slot: slot, psychDay: yesterday, snoozedAt: yesterday)
        ctx.insert(stale)
        #expect(slot.snoozes.count == 1)

        // Create a new snooze today — stale one should be cleaned up
        let time = date(year: 2026, month: 3, day: 5, hour: 10)
        SlotSnooze.create(slot: slot, at: time, in: ctx)

        // Only today's snooze should remain
        #expect(slot.snoozes.count == 1)
        #expect(
            Calendar.current.isDate(
                slot.snoozes[0].psychDay, inSameDayAs: date(year: 2026, month: 3, day: 5)))
    }

    @Test("cross-midnight stale cleanup: snooze NOT deleted while slot still active at 12:30am")
    @MainActor func create_crossMidnight_snoozeKeptWhileSlotActive() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Slot: 11pm–1am (crosses midnight)
        let slot = makeSlotAndInsert(startHour: 23, endHour: 1, in: ctx)

        // First snooze at 12am Jan 1 (slot is active: in 11pm Dec 31 – 1am Jan 1 window)
        let snoozeTime = date(year: 2026, month: 1, day: 1, hour: 0)
        let snooze = SlotSnooze.create(slot: slot, at: snoozeTime, in: ctx)
        #expect(snooze != nil)
        #expect(slot.snoozes.count == 1)

        // Attempt another create at 12:30am Jan 1 — slot still active, stale check should NOT delete existing snooze
        // (resolvedSlotEnd = 1am Jan 1, which is > 12:30am, so NOT stale)
        // However create will return nil since a snooze already exists... actually it would create another one.
        // The real test: the existing snooze should not be deleted at 12:30am.
        let at1230 = date(year: 2026, month: 1, day: 1, hour: 0, minute: 30)
        _ = SlotSnooze.create(slot: slot, at: at1230, in: ctx)
        // Both the original and new snooze exist (cleanup didn't delete the live one)
        let dec31Snoozes = slot.snoozes.filter {
            Calendar.current.isDate($0.psychDay, inSameDayAs: date(year: 2025, month: 12, day: 31))
        }
        #expect(!dec31Snoozes.isEmpty)
    }

    @Test("cross-midnight stale cleanup: snooze IS deleted after slot ends at 1:30am")
    @MainActor func create_crossMidnight_snoozeDeletedAfterSlotEnds() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Slot: 11pm–1am (crosses midnight). We need a different active slot to trigger create.
        let nightSlot = makeSlotAndInsert(startHour: 23, endHour: 1, in: ctx)

        // Insert a stale cross-midnight snooze manually (for Dec 31, slot ended at 1am Jan 1)
        let dec31 = date(year: 2025, month: 12, day: 31)
        let staleSnooze = SlotSnooze(
            slot: nightSlot, psychDay: dec31, snoozedAt: date(year: 2026, month: 1, day: 1, hour: 0)
        )
        ctx.insert(staleSnooze)
        #expect(nightSlot.snoozes.count == 1)

        // `Time` it's 1:30am Jan 1 — slot has ended (resolvedSlotEnd = 1am Jan 1 < 1:30am)
        // Trigger cleanup by attempting create (which will return nil since 1:30am is outside the 11pm-1am window)
        let at130am = date(year: 2026, month: 1, day: 1, hour: 1, minute: 30)
        let result = SlotSnooze.create(slot: nightSlot, at: at130am, in: ctx)
        #expect(result == nil)  // 1:30am is outside 11pm-1am window

        // The stale snooze should have been deleted
        #expect(nightSlot.snoozes.isEmpty)
    }
}
