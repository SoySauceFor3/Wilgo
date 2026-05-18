import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import Wilgo

@Suite(.serialized)
final class SlotStartNotificationSchedulerTests {
    // MARK: - Helpers

    private func tod(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2000
        c.month = 1
        c.day = 1
        c.hour = hour
        c.minute = minute
        c.second = 0
        return Calendar.current.date(from: c)!
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        c.minute = minute
        c.second = 0
        return Calendar.current.date(from: c)!
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, SlotSnooze.self, Tag.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    @MainActor
    private func makeCommitment(
        slots slotDefs: [(start: Int, end: Int)],
        targetCount: Int = 3,
        isRemindersEnabled: Bool = true,
        in ctx: ModelContext
    ) -> Commitment {
        let anchor = date(year: 2026, month: 1, day: 1)
        let slots = slotDefs.map { Slot(start: tod(hour: $0.start), end: tod(hour: $0.end)) }
        let c = Commitment(
            title: "Test",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: slots,
            target: Target(count: targetCount),
            isRemindersEnabled: isRemindersEnabled
        )
        ctx.insert(c)
        slots.forEach { ctx.insert($0) }
        return c
    }

    @MainActor
    private func addCheckIn(to c: Commitment, at date: Date, in ctx: ModelContext) {
        let checkIn = CheckIn(commitment: c, createdAt: date)
        ctx.insert(checkIn)
        c.checkIns.append(checkIn)
    }

    // MARK: - startTimeInRangeToCommitments tests

    @Test("single commitment with one slot returns its upcoming start")
    @MainActor func startTimeInRangeToCommitments_singleCommitment_oneSlot_returnsSlotStart() throws
    {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 7)

        let result = SlotStartNotificationScheduler.startTimeInRangeToCommitments(
            for: [c], from: now)

        let expected = date(year: 2026, month: 3, day: 5, hour: 9)
        #expect(result[expected] != nil)
        #expect(result[expected]?.count == 1)
    }

    @Test("two commitments at the same slot start are grouped into one entry")
    @MainActor func startTimeInRangeToCommitments_twoCommitmentsAtSameTime_groupedTogether() throws
    {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c1 = makeCommitment(slots: [(9, 11)], in: ctx)
        let c2 = makeCommitment(slots: [(9, 11)], in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 7)

        let result = SlotStartNotificationScheduler.startTimeInRangeToCommitments(
            for: [c1, c2], from: now)

        let expected = date(year: 2026, month: 3, day: 5, hour: 9)
        #expect(result[expected]?.count == 2)
    }

    @Test("commitment with reminders disabled is excluded")
    @MainActor func startTimeInRangeToCommitments_remindersDisabled_excluded() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], isRemindersEnabled: false, in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 7)

        let result = SlotStartNotificationScheduler.startTimeInRangeToCommitments(
            for: [c], from: now)

        #expect(result.isEmpty)
    }

    @Test("commitment whose goal is already met is excluded")
    @MainActor func startTimeInRangeToCommitments_goalAlreadyMet_excluded() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], targetCount: 1, in: ctx)
        // One check-in satisfies the daily target of 1
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 8), in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 7)

        let result = SlotStartNotificationScheduler.startTimeInRangeToCommitments(
            for: [c], from: now)

        #expect(result.isEmpty)
    }

    @Test("slot starts beyond horizon are excluded")
    @MainActor func startTimeInRangeToCommitments_beyondHorizon_excluded() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], in: ctx)
        // horizon is before any slot starts
        let now = date(year: 2026, month: 3, day: 5, hour: 7)
        let tinyHorizon = date(year: 2026, month: 3, day: 5, hour: 8)

        let result = SlotStartNotificationScheduler.startTimeInRangeToCommitments(
            for: [c], from: now, horizon: tinyHorizon)

        #expect(result.isEmpty)
    }

    @Test("results are capped at maxPendingCount")
    @MainActor func startTimeInRangeToCommitments_cappedAtMax() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // 4 slots/day × 14 days >> 48
        let c = makeCommitment(
            slots: [(8, 9), (11, 12), (13, 14), (18, 19)], targetCount: 99, in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 7)

        let result = SlotStartNotificationScheduler.startTimeInRangeToCommitments(
            for: [c], from: now)

        #expect(result.count == SlotStartNotificationScheduler.maxPendingCount)
    }

    // MARK: - makeRequest tests

    @Test("single commitment notification has correct title")
    @MainActor func makeRequest_singleCommitment_titleContainsCommitmentTitle() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], in: ctx)
        c.title = "Morning Run"
        let fireDate = date(year: 2026, month: 3, day: 5, hour: 9)

        let request = SlotStartNotificationScheduler.makeRequest(for: [c], at: fireDate)

        #expect(request.content.title.contains("Morning Run"))
    }

    @Test("multi-commitment notification title contains count")
    @MainActor func makeRequest_multiCommitment_titleContainsCount() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c1 = makeCommitment(slots: [(9, 11)], in: ctx)
        let c2 = makeCommitment(slots: [(9, 11)], in: ctx)
        let fireDate = date(year: 2026, month: 3, day: 5, hour: 9)

        let request = SlotStartNotificationScheduler.makeRequest(for: [c1, c2], at: fireDate)

        #expect(request.content.title.contains("2"))
    }

    @Test("single commitment with encouragement uses it as body")
    @MainActor func makeRequest_singleWithEncouragement_bodyIsEncouragement() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], in: ctx)
        c.encouragements = ["You got this!"]
        let fireDate = date(year: 2026, month: 3, day: 5, hour: 9)

        let request = SlotStartNotificationScheduler.makeRequest(for: [c], at: fireDate)

        #expect(request.content.body == "You got this!")
    }

    @Test("notification identifier encodes the fire date")
    @MainActor func makeRequest_identifierEncodesFireDate() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], in: ctx)
        let fireDate = date(year: 2026, month: 3, day: 5, hour: 9)

        let request = SlotStartNotificationScheduler.makeRequest(for: [c], at: fireDate)

        #expect(
            request.identifier.hasPrefix(
                SlotStartNotificationScheduler.notificationIdentifierPrefix))
    }

    @Test("commitment with goal met and continueRemindersAfterGoalMet=true is included")
    @MainActor func startTimeInRangeToCommitments_goalMet_continueEnabled_included() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], targetCount: 1, in: ctx)
        c.continueRemindersAfterGoalMet = true
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 8), in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 7)

        let result = SlotStartNotificationScheduler.startTimeInRangeToCommitments(
            for: [c], from: now)

        let expected = date(year: 2026, month: 3, day: 5, hour: 9)
        #expect(result[expected] != nil)
    }

    @Test("commitment with goal met and continueRemindersAfterGoalMet=false is excluded (default)")
    @MainActor func startTimeInRangeToCommitments_goalMet_continueDisabled_excluded() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], targetCount: 1, in: ctx)
        c.continueRemindersAfterGoalMet = false
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 8), in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 7)

        let result = SlotStartNotificationScheduler.startTimeInRangeToCommitments(
            for: [c], from: now)

        #expect(result.isEmpty)
    }
}
