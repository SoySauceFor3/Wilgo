import Foundation
import SwiftData
import Testing

@testable import Wilgo

// MARK: - Helpers

private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = hour
    comps.second = 0
    return Calendar.current.date(from: comps)!
}

private func timeOfDay(hour: Int) -> Date {
    date(year: 2000, month: 1, day: 1, hour: hour)
}

@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema([Commitment.self, Slot.self, CheckIn.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

private func makeSlot(startHour: Int, endHour: Int) -> Slot {
    Slot(start: timeOfDay(hour: startHour), end: timeOfDay(hour: endHour))
}

@MainActor
private func makeCommitment(
    in ctx: ModelContext,
    title: String = "Test",
    slots: [Slot] = [],
    skipCreditCount: Int = 3,
    cycle: Cycle = .daily,
    punishment: String? = nil
) -> Commitment {
    let commitment = Commitment(
        title: title,
        slots: slots,
        skipCreditCount: skipCreditCount,
        cycle: cycle,
        punishment: punishment,
        goalCountPerDay: slots.count
    )
    ctx.insert(commitment)
    for slot in slots { ctx.insert(slot) }
    return commitment
}

// MARK: - Tests

@Suite("SkipCredit", .serialized)
struct SkipCreditTests {

    // MARK: - creditsUsedInCycle

    @Suite("SkipCredit — creditsUsedInCycle")
    final class CreditsUsedInCycleTests {

        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)
        init() { UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey) }
        deinit { UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey) }

        let psychDay = date(year: 2026, month: 3, day: 5)

        // A single-day window so that `creditsUsedInCycle` only examines one psych day.
        @Test("no check-ins, one slot → 1 credit burned")
        @MainActor func nothingCompleted() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(in: ctx, slots: [makeSlot(startHour: 9, endHour: 10)])
            let used = SkipCredit.creditsUsedInCycle(for: commitment, until: psychDay)
            #expect(used == 1)
        }

        // A single-day window so that `creditsUsedInCycle` only examines one psych day.
        @Test("no check-ins, two slots → 2 credits burned")
        @MainActor func nothingCompletedTwoSlots() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(
                in: ctx,
                slots: [makeSlot(startHour: 7, endHour: 8), makeSlot(startHour: 14, endHour: 15)])
            let used = SkipCredit.creditsUsedInCycle(for: commitment, until: psychDay)
            #expect(used == 2)
        }

        // A single-day window so that `creditsUsedInCycle` only examines one psych day.
        @Test("one of two slots completed → 1 credit burned")
        @MainActor func partialCompletion() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(
                in: ctx,
                slots: [makeSlot(startHour: 7, endHour: 8), makeSlot(startHour: 14, endHour: 15)])
            ctx.insert(
                CheckIn(
                    commitment: commitment, createdAt: date(year: 2026, month: 3, day: 5, hour: 7)))
            let used = SkipCredit.creditsUsedInCycle(for: commitment, until: psychDay)
            #expect(used == 1)
        }

        @Test("all slots completed → 0 credits burned")
        @MainActor func fullyCompleted() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(in: ctx, slots: [makeSlot(startHour: 9, endHour: 10)])
            ctx.insert(
                CheckIn(
                    commitment: commitment, createdAt: date(year: 2026, month: 3, day: 5, hour: 9)))
            let used = SkipCredit.creditsUsedInCycle(for: commitment, until: psychDay)
            #expect(used == 0)
        }

        @Test("no slots → 0 credits burned")
        @MainActor func noSlots() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(in: ctx)
            let used = SkipCredit.creditsUsedInCycle(for: commitment, until: psychDay)
            #expect(used == 0)
        }

        @Test("weekly cycle: credits accumulate across multiple days in the period")
        @MainActor func weeklyCycleAccumulatesAcrossDays() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            // Anchor on Monday (weekday 2). Period: Mar 2 (Mon) – Mar 8 (Sun).
            // Check-in on Mar 3 only → Mar 2 (missed) + Mar 3 (done) + ... up to Mar 5 (2 missed).
            let commitment = makeCommitment(
                in: ctx,
                slots: [makeSlot(startHour: 9, endHour: 10)],
                skipCreditCount: 5,
                cycle: .weekly(weekday: 2))
            // Mar 2 and Mar 4 missed; Mar 3 and Mar 5 completed.
            ctx.insert(
                CheckIn(
                    commitment: commitment, createdAt: date(year: 2026, month: 3, day: 3, hour: 9)))
            ctx.insert(
                CheckIn(
                    commitment: commitment, createdAt: date(year: 2026, month: 3, day: 5, hour: 9)))
            // Mar 2 (missed) + Mar 4 (missed) = 2 credits burned, up to Mar 5.
            let used = SkipCredit.creditsUsedInCycle(
                for: commitment, until: date(year: 2026, month: 3, day: 5))
            #expect(used == 2)
        }
    }

    // MARK: - creditsRemaining

    @Suite("SkipCredit — creditsRemaining")
    final class CreditsRemainingTests {

        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)
        init() { UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey) }
        deinit { UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey) }

        let psychDay = date(year: 2026, month: 3, day: 5)

        @Test("no credits used → full allowance remaining")
        @MainActor func fullAllowanceWhenNothingUsed() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            // All slots completed → 0 burned.
            let commitment = makeCommitment(
                in: ctx, slots: [makeSlot(startHour: 9, endHour: 10)], skipCreditCount: 3)
            ctx.insert(
                CheckIn(
                    commitment: commitment, createdAt: date(year: 2026, month: 3, day: 5, hour: 9)))
            let remaining = SkipCredit.creditsRemaining(for: commitment, until: psychDay)
            #expect(remaining == 3)
        }

        @Test("credits partially used → reduced allowance")
        @MainActor func partiallyUsed() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(
                in: ctx,
                slots: [makeSlot(startHour: 7, endHour: 8), makeSlot(startHour: 14, endHour: 15)],
                skipCreditCount: 3)
            // One slot done, one missed → 1 burned.
            ctx.insert(
                CheckIn(
                    commitment: commitment, createdAt: date(year: 2026, month: 3, day: 5, hour: 7)))
            let remaining = SkipCredit.creditsRemaining(for: commitment, until: psychDay)
            #expect(remaining == 2)
        }

        @Test("all credits exhausted → 0")
        @MainActor func allCreditsExhausted() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            // 1 slot missed, 1 credit allowed → 0 remaining.
            let commitment = makeCommitment(
                in: ctx, slots: [makeSlot(startHour: 9, endHour: 10)], skipCreditCount: 1)
            // No check-in → 1 credit burned.
            let remaining = SkipCredit.creditsRemaining(for: commitment, until: psychDay)
            #expect(remaining == 0)
        }

        @Test("over budget → clamped to 0, not negative")
        @MainActor func overBudgetClampedToZero() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            // 2 slots missed, only 1 credit allowed → clamped at 0.
            let commitment = makeCommitment(
                in: ctx,
                slots: [makeSlot(startHour: 7, endHour: 8), makeSlot(startHour: 14, endHour: 15)],
                skipCreditCount: 1)
            let remaining = SkipCredit.creditsRemaining(for: commitment, until: psychDay)
            #expect(remaining == 0)
        }
    }

    // MARK: - notificationLine

    @Suite("SkipCredit — notificationLine")
    final class NotificationLineTests {

        private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)
        init() { UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey) }
        deinit { UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey) }

        let psychDay = date(year: 2026, month: 3, day: 5)

        @Test("nothing completed → ❌ icon")
        @MainActor func nothingCompletedUsesXIcon() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(
                in: ctx, title: "Exercise", slots: [makeSlot(startHour: 9, endHour: 10)],
                skipCreditCount: 3)
            let line = SkipCredit.notificationLine(for: commitment, on: psychDay)
            #expect(line.hasPrefix("❌"))
        }

        @Test("partially completed → ⚠️ icon")
        @MainActor func partiallyCompletedUsesWarningIcon() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(
                in: ctx, title: "Exercise",
                slots: [makeSlot(startHour: 7, endHour: 8), makeSlot(startHour: 14, endHour: 15)],
                skipCreditCount: 3)
            ctx.insert(
                CheckIn(
                    commitment: commitment, createdAt: date(year: 2026, month: 3, day: 5, hour: 7)))
            let line = SkipCredit.notificationLine(for: commitment, on: psychDay)
            #expect(line.hasPrefix("⚠️"))
        }

        @Test("within budget → positive delta")
        @MainActor func withinBudgetShowsPositiveDelta() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            // 0 done, 1 slot → 1 credit used; allowance = 3 → +2 remaining.
            let commitment = makeCommitment(
                in: ctx, title: "Reading", slots: [makeSlot(startHour: 9, endHour: 10)],
                skipCreditCount: 3)
            let line = SkipCredit.notificationLine(for: commitment, on: psychDay)
            #expect(line.contains("+2"))
        }

        @Test("over budget → negative delta")
        @MainActor func overBudgetShowsNegativeDelta() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            // 2 slots missed, allowance = 1 → 1 over budget → −1.
            let commitment = makeCommitment(
                in: ctx, title: "Exercise",
                slots: [makeSlot(startHour: 7, endHour: 8), makeSlot(startHour: 14, endHour: 15)],
                skipCreditCount: 1)
            let line = SkipCredit.notificationLine(for: commitment, on: psychDay)
            #expect(line.contains("−1"))
        }

        @Test("exactly at budget → +0 delta")
        @MainActor func exactlyAtBudgetShowsZeroDelta() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            // 1 slot missed, allowance = 1 → 1 used, 0 remaining → +0.
            let commitment = makeCommitment(
                in: ctx, title: "Exercise", slots: [makeSlot(startHour: 9, endHour: 10)],
                skipCreditCount: 1)
            let line = SkipCredit.notificationLine(for: commitment, on: psychDay)
            #expect(line.contains("+0"))
        }

        @Test("punishment appended only when credits exhausted and punishment is set")
        @MainActor func punishmentAppendedWhenExhausted() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(
                in: ctx, title: "Exercise", slots: [makeSlot(startHour: 9, endHour: 10)],
                skipCreditCount: 0, punishment: "Give robaroba 20 RMB")
            let line = SkipCredit.notificationLine(for: commitment, on: psychDay)
            #expect(line.hasSuffix("· Give robaroba 20 RMB"))
        }

        @Test("punishment not appended when credits still available")
        @MainActor func punishmentOmittedWhenCreditAvailable() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(
                in: ctx, title: "Exercise", slots: [makeSlot(startHour: 9, endHour: 10)],
                skipCreditCount: 3, punishment: "Give robaroba 20 RMB")
            let line = SkipCredit.notificationLine(for: commitment, on: psychDay)
            #expect(!line.contains("Give robaroba 20 RMB"))
        }

        @Test("punishment nil → no punishment segment")
        @MainActor func noPunishmentWhenNil() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment(
                in: ctx, title: "Exercise", slots: [makeSlot(startHour: 9, endHour: 10)],
                skipCreditCount: 0, punishment: nil)
            let line = SkipCredit.notificationLine(for: commitment, on: psychDay)
            #expect(!line.contains("·\u{A0}"))  // no trailing segment after delta
            // The line should still end with the delta, not a punishment.
            #expect(line.last?.isLetter == false || line.last?.isNumber == true)
        }

        @Test("line format matches expected pattern")
        @MainActor func lineFormatMatchesPattern() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            // 0 done out of 2, 5 credits used/4 allowance → −1.
            let commitment = makeCommitment(
                in: ctx, title: "Exercise",
                slots: [makeSlot(startHour: 7, endHour: 8), makeSlot(startHour: 14, endHour: 15)],
                skipCreditCount: 4, punishment: "Give robaroba 20 RMB")
            // Burn 5 credits: need 5 unfinished across prior days using a weekly cycle.
            // Simpler: use a weekly cycle and check in so exactly 5 credits are burned.
            // Instead, verify the format with a fresh daily cycle where 2 are burned, allowance 1.
            let singleSlotCommitment = makeCommitment(
                in: ctx, title: "Exercise",
                slots: [makeSlot(startHour: 7, endHour: 8), makeSlot(startHour: 14, endHour: 15)],
                skipCreditCount: 4, punishment: "Give robaroba 20 RMB")
            let line = SkipCredit.notificationLine(for: singleSlotCommitment, on: psychDay)
            // Should contain title, done/required, used/allowance, delta.
            #expect(line.contains("Exercise"))
            #expect(line.contains("0/2"))
            #expect(line.contains("2/4cr"))
            #expect(line.contains("+2"))
        }
    }
}
