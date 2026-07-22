import Foundation
import SwiftData
import Testing
@testable import Wilgo

// Tests for the derivation logic that `CommitmentHeatmapInfoCard` performs from
// (commitment, range, rangeKind) — replacing the frozen `PeriodData` snapshot it
// used to take. The card is a SwiftUI View, so we test the underlying derivations
// it delegates to (`checkInsInRange`, `expectedGoalPerPeriod`) plus the one piece
// of new inline logic it owns (`isBeforeCreation`), extracted as a testable helper.

@MainActor
private func makeDailyCommitment(
    ctx: ModelContext,
    targetCount: Int = 2,
    createdAt: Date = Date()
) -> Commitment {
    let commitment = Commitment(
        title: "Run",
        createdAt: createdAt,
        cycle: Cycle.makeDefault(.daily),
        slots: [],
        target: Target(count: targetCount)
    )
    ctx.insert(commitment)
    return commitment
}

@MainActor
@discardableResult
private func addCheckIn(_ commitment: Commitment, at createdAt: Date, ctx: ModelContext) -> CheckIn {
    let ci = CheckIn(commitment: commitment, createdAt: createdAt, source: .app)
    ctx.insert(ci)
    commitment.checkIns.append(ci)
    return ci
}

@MainActor
struct InfoCardDerivationTests {
    // MARK: liveCheckIns — range filter

    /// The card's live check-in list = commitment.checkInsInRange over [range.lowerBound, range.upperBound),
    /// returning exactly the check-ins whose psychDay falls in the half-open range, sorted by createdAt.
    @Test func liveCheckInsFiltersToRangeAndSorts() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let cal = Time.calendar
        let day0 = Time.startOfDay(for: Date())
        let dayBefore = try #require(cal.date(byAdding: .day, value: -1, to: day0))
        let dayAfter = try #require(cal.date(byAdding: .day, value: 1, to: day0))

        let commitment = makeDailyCommitment(ctx: ctx)

        // Two inside day0 (out of order), one the day before, one the day after.
        let inside2 = addCheckIn(commitment, at: day0.addingTimeInterval(11 * 3600), ctx: ctx)
        let inside1 = addCheckIn(commitment, at: day0.addingTimeInterval(9 * 3600), ctx: ctx)
        addCheckIn(commitment, at: dayBefore.addingTimeInterval(9 * 3600), ctx: ctx)
        addCheckIn(commitment, at: dayAfter.addingTimeInterval(9 * 3600), ctx: ctx)

        // Range for day0 only: [day0, dayAfter)
        let result = commitment.checkInsInRange(startPsychDay: day0, endPsychDay: dayAfter)

        #expect(result.count == 2)
        #expect(result.map(\.id) == [inside1.id, inside2.id])  // sorted by createdAt ascending
    }

    // MARK: goal — expectedGoalPerPeriod

    /// The card's goal derivation matches Heatmap.expectedGoalPerPeriod for the (targetKind, rangeKind) pair.
    /// daily target of 2, viewed at daily granularity → goal 2; at weekly → 14.
    @Test func goalMatchesExpectedGoalPerPeriod() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let commitment = makeDailyCommitment(ctx: ctx, targetCount: 2)

        let dailyGoal = Heatmap.expectedGoalPerPeriod(
            target: commitment.target, cycleKind: commitment.cycle.kind, periodKind: .daily)
        let weeklyGoal = Heatmap.expectedGoalPerPeriod(
            target: commitment.target, cycleKind: commitment.cycle.kind, periodKind: .weekly)

        #expect(dailyGoal == 2)
        #expect(weeklyGoal == 14)
    }

    /// A non-positive target count yields no goal (nil), which the card renders as the plain check-in count.
    @Test func goalIsNilForZeroTarget() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let commitment = makeDailyCommitment(ctx: ctx, targetCount: 0)

        let goal = Heatmap.expectedGoalPerPeriod(
            target: commitment.target, cycleKind: commitment.cycle.kind, periodKind: .daily)

        #expect(goal == nil)
    }

    // MARK: isBeforeCreation — boundary

    /// isBeforeCreation is true when the range ends on or before the start of the creation day,
    /// and false once the range extends past it.
    @Test func isBeforeCreationBoundary() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let cal = Time.calendar
        let createdDay = Time.startOfDay(for: Date())
        let commitment = makeDailyCommitment(ctx: ctx, createdAt: createdDay.addingTimeInterval(9 * 3600))

        let dayBefore = try #require(cal.date(byAdding: .day, value: -1, to: createdDay))
        let dayAfter = try #require(cal.date(byAdding: .day, value: 1, to: createdDay))

        // A period entirely before creation: [dayBefore, createdDay). upperBound == createdDay → before.
        #expect(
            CommitmentHeatmapInfoCard.isBeforeCreation(
                rangeUpperBound: createdDay, commitment: commitment) == true)

        // The creation day's own period: [createdDay, dayAfter). upperBound past creation start → not before.
        #expect(
            CommitmentHeatmapInfoCard.isBeforeCreation(
                rangeUpperBound: dayAfter, commitment: commitment) == false)

        // A period well before: [dayBefore-…, dayBefore). → before.
        #expect(
            CommitmentHeatmapInfoCard.isBeforeCreation(
                rangeUpperBound: dayBefore, commitment: commitment) == true)
    }

    // MARK: shouldShowGoalSummary — chrome gating

    /// The "N / goal · status" summary shows only when heatmap chrome is on, a goal
    /// exists, and the period granularity matches the commitment's target cycle kind.
    @Test func shouldShowGoalSummaryGating() {
        // Chrome on + goal + matching kinds → show.
        #expect(
            CommitmentHeatmapInfoCard.shouldShowGoalSummary(
                showsHeatmapChrome: true, goal: 2, targetKind: .daily, rangeKind: .daily) == true)

        // Chrome OFF (FCR) → hide even when goal + kinds match.
        #expect(
            CommitmentHeatmapInfoCard.shouldShowGoalSummary(
                showsHeatmapChrome: false, goal: 2, targetKind: .daily, rangeKind: .daily) == false)

        // No goal → hide.
        #expect(
            CommitmentHeatmapInfoCard.shouldShowGoalSummary(
                showsHeatmapChrome: true, goal: nil, targetKind: .daily, rangeKind: .daily) == false)

        // Kind mismatch (goal is only a color artifact) → hide.
        #expect(
            CommitmentHeatmapInfoCard.shouldShowGoalSummary(
                showsHeatmapChrome: true, goal: 14, targetKind: .daily, rangeKind: .weekly) == false)
    }
}
