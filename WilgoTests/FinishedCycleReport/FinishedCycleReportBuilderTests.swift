import Foundation
import SwiftData
import Testing
@testable import Wilgo

private func date(
    year: Int,
    month: Int,
    day: Int,
    hour: Int = 0,
    minute: Int = 0
) -> Date {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = hour
    comps.minute = minute
    comps.second = 0
    return Calendar.current.date(from: comps)!
}

@Suite(.serialized)
struct FinishedCycleReportBuilderTests: ~Copyable {
    @Test("build uses multiple tokens to compensate one cycle")
    @MainActor
    func buildCompensatesWithMultipleTokens() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let anchor = date(year: 2026, month: 2, day: 1)
        let targetCycle = Cycle(kind: .daily, referencePsychDay: anchor)
        let commitment = Commitment(
            title: "Read",
            cycle: targetCycle,
            slots: [],
            target: Target(count: 5),
        )
        ctx.insert(commitment)

        for hour in [9, 10, 11] {
            let checkIn = CheckIn(
                commitment: commitment, createdAt: date(year: 2026, month: 2, day: 1, hour: hour))
            ctx.insert(checkIn)
            commitment.checkIns.append(checkIn)
        }

        let t1 = PositivityToken(reason: "a", createdAt: date(year: 2026, month: 1, day: 1))
        let t2 = PositivityToken(reason: "b", createdAt: date(year: 2026, month: 1, day: 2))
        ctx.insert(t1)
        ctx.insert(t2)

        let preReport = PreTokenReportBuilder.build(
            commitments: [commitment],
            startPsychDay: date(year: 2026, month: 2, day: 1),
            endPsychDay: date(year: 2026, month: 2, day: 2)
        )
        let report = AfterPositivityTokenReportBuilder.apply(
            to: preReport,
            allTokens: [t1, t2],
            monthlyCap: 10
        )

        #expect(report.count == 1)
        let cycle = try #require(report.first?.cycles.first)
        #expect(cycle.actualCheckIns == 3)
        #expect(cycle.aidedByPositivityTokenCount == 2)
        #expect(cycle.compensatedCheckIns == 5)
        #expect(cycle.metTarget)
    }

    @Test("PT usage summary shows before and after availability")
    @MainActor
    func usageSummaryShowsBeforeAndAfterAvailability() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let anchor = date(year: 2026, month: 2, day: 1)
        let targetCycle = Cycle(kind: .daily, referencePsychDay: anchor)
        let commitment = Commitment(
            title: "Read",
            cycle: targetCycle,
            slots: [],
            target: Target(count: 5),
        )
        ctx.insert(commitment)

        for hour in [9, 10, 11] {
            let checkIn = CheckIn(
                commitment: commitment,
                createdAt: date(year: 2026, month: 2, day: 1, hour: hour)
            )
            ctx.insert(checkIn)
            commitment.checkIns.append(checkIn)
        }

        let alreadyUsed = PositivityToken(
            reason: "already used", createdAt: date(year: 2026, month: 1, day: 1))
        alreadyUsed.status = .used
        alreadyUsed.dayOfStatus = date(year: 2026, month: 2, day: 1)
        let t1 = PositivityToken(reason: "a", createdAt: date(year: 2026, month: 1, day: 2))
        let t2 = PositivityToken(reason: "b", createdAt: date(year: 2026, month: 1, day: 3))
        let t3 = PositivityToken(reason: "c", createdAt: date(year: 2026, month: 1, day: 4))

        let preReport = PreTokenReportBuilder.build(
            commitments: [commitment],
            startPsychDay: date(year: 2026, month: 2, day: 1),
            endPsychDay: date(year: 2026, month: 2, day: 2)
        )
        let finalReport = AfterPositivityTokenReportBuilder.apply(
            to: preReport,
            allTokens: [alreadyUsed, t1, t2, t3],
            monthlyCap: 3
        )

        let summary = AfterPositivityTokenReportBuilder.usageSummary(
            preReport: preReport,
            finalReport: finalReport,
            allTokens: [alreadyUsed, t1, t2, t3],
            monthlyCap: 3
        )

        #expect(summary.activeTokensBefore == 3)
        #expect(summary.activeTokensAfter == 1)
        #expect(summary.availableBudgetBefore == 2)
        #expect(summary.availableBudgetAfter == 0)
        #expect(summary.totalTokensUsed == 2)
    }

    @Test("PT step preparation freezes report and summary together")
    @MainActor
    func positivityTokenStepPreparationFreezesReportAndSummaryTogether() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let anchor = date(year: 2026, month: 2, day: 1)
        let targetCycle = Cycle(kind: .daily, referencePsychDay: anchor)
        let commitment = Commitment(
            title: "Read",
            cycle: targetCycle,
            slots: [],
            target: Target(count: 5),
        )
        ctx.insert(commitment)

        for hour in [9, 10, 11] {
            let checkIn = CheckIn(
                commitment: commitment,
                createdAt: date(year: 2026, month: 2, day: 1, hour: hour)
            )
            ctx.insert(checkIn)
            commitment.checkIns.append(checkIn)
        }

        let t1 = PositivityToken(reason: "a", createdAt: date(year: 2026, month: 1, day: 1))
        let t2 = PositivityToken(reason: "b", createdAt: date(year: 2026, month: 1, day: 2))
        ctx.insert(t1)
        ctx.insert(t2)

        let preReport = PreTokenReportBuilder.build(
            commitments: [commitment],
            startPsychDay: date(year: 2026, month: 2, day: 1),
            endPsychDay: date(year: 2026, month: 2, day: 2)
        )

        let prepared = PositivityTokenStepPreparation.prepare(
            preTokenReport: preReport,
            allTokens: [t1, t2],
            monthlyCap: 10
        )

        let cycle = try #require(prepared.finalReport.first?.cycles.first)
        #expect(cycle.aidedByPositivityTokenCount == 2)
        #expect(prepared.usageSummary.totalTokensUsed == 2)
        #expect(prepared.usageSummary.activeTokensBefore == 2)
        #expect(prepared.usageSummary.activeTokensAfter == 0)
    }

    @Test("no tokens → no compensation")
    @MainActor
    func noTokensNoCompensation() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let anchor = date(year: 2026, month: 2, day: 1)
        let targetCycle = Cycle(kind: .daily, referencePsychDay: anchor)
        let commitment = Commitment(
            title: "Run",
            cycle: targetCycle,
            slots: [],
            target: Target(count: 3),
        )
        ctx.insert(commitment)

        let checkIn = CheckIn(
            commitment: commitment, createdAt: date(year: 2026, month: 2, day: 1, hour: 9))
        ctx.insert(checkIn)
        commitment.checkIns.append(checkIn)

        let preReport = PreTokenReportBuilder.build(
            commitments: [commitment],
            startPsychDay: date(year: 2026, month: 2, day: 1),
            endPsychDay: date(year: 2026, month: 2, day: 2)
        )
        let report = AfterPositivityTokenReportBuilder.apply(
            to: preReport,
            allTokens: [],
            monthlyCap: 10
        )

        #expect(report.count == 1)
        let cycle = try #require(report.first?.cycles.first)
        #expect(cycle.actualCheckIns == 1)
        #expect(cycle.aidedByPositivityTokenCount == 0)
        #expect(cycle.metTarget == false)
    }

    @Test(
        "target disabled: effectiveTargetMode disabled, targetCheckIns preserves real count, no PT")
    @MainActor func targetDisabled_reportPreservesCount() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let anchor = date(year: 2026, month: 2, day: 1)
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [],
            target: Target(count: 3, mode: .disabled)
        )
        ctx.insert(c)
        let checkIn = CheckIn(commitment: c, createdAt: date(year: 2026, month: 2, day: 1, hour: 9))
        ctx.insert(checkIn)
        c.checkIns.append(checkIn)

        let preReport = PreTokenReportBuilder.build(
            commitments: [c],
            startPsychDay: date(year: 2026, month: 2, day: 1),
            endPsychDay: date(year: 2026, month: 2, day: 2)
        )

        #expect(preReport.count == 1)
        let cycle = try #require(preReport.first?.cycles.first)
        #expect(cycle.actualCheckIns == 1)
        #expect(cycle.targetCheckIns == 3)
        #expect(cycle.effectiveTargetMode == .disabled)
        #expect(cycle.consumedPTReasons.isEmpty)
    }

    @Test("target disabled: appears in report but receives no PT compensation")
    @MainActor func targetDisabled_receivesNoPTCompensation() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let anchor = date(year: 2026, month: 2, day: 1)
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [],
            target: Target(count: 3, mode: .disabled)
        )
        ctx.insert(c)
        let t1 = PositivityToken(reason: "a", createdAt: date(year: 2026, month: 1, day: 1))
        let t2 = PositivityToken(reason: "b", createdAt: date(year: 2026, month: 1, day: 2))
        ctx.insert(t1)
        ctx.insert(t2)

        let preReport = PreTokenReportBuilder.build(
            commitments: [c],
            startPsychDay: date(year: 2026, month: 2, day: 1),
            endPsychDay: date(year: 2026, month: 2, day: 2)
        )
        let report = AfterPositivityTokenReportBuilder.apply(
            to: preReport,
            allTokens: [t1, t2],
            monthlyCap: 10
        )

        #expect(report.count == 1)
        let cycle = try #require(report.first?.cycles.first)
        #expect(cycle.effectiveTargetMode == .disabled)
        #expect(cycle.aidedByPositivityTokenCount == 0)
        #expect(t1.status == .active)
        #expect(t2.status == .active)
    }

    @Test("start >= end returns empty report")
    @MainActor
    func invalidDateRangeReturnsEmpty() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let anchor = date(year: 2026, month: 2, day: 1)
        let targetCycle = Cycle(kind: .daily, referencePsychDay: anchor)
        let commitment = Commitment(
            title: "Read",
            cycle: targetCycle,
            slots: [],
            target: Target(count: 1),
        )
        ctx.insert(commitment)

        let report = PreTokenReportBuilder.build(
            commitments: [commitment],
            startPsychDay: date(year: 2026, month: 2, day: 2),
            endPsychDay: date(year: 2026, month: 2, day: 1)
        )
        #expect(report.isEmpty)
    }
}
