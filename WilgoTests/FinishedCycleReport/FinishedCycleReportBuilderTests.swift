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

@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema([
        Commitment.self,
        Slot.self,
        CheckIn.self,
        PositivityToken.self,
        Tag.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

@Suite("FinishedCycleReportBuilder", .serialized)
struct FinishedCycleReportBuilderTests: ~Copyable {
    @Test("build uses multiple tokens to compensate one cycle")
    @MainActor
    func buildCompensatesWithMultipleTokens() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let anchor = date(year: 2026, month: 2, day: 1)
        let targetCycle = Cycle(kind: .daily, referencePsychDay: anchor)
        let commitment = Commitment(
            title: "Read",
            slots: [],
            target: QuantifiedCycle(cycle: targetCycle, count: 5),
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

    @Test("no tokens → no compensation")
    @MainActor
    func noTokensNoCompensation() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let anchor = date(year: 2026, month: 2, day: 1)
        let targetCycle = Cycle(kind: .daily, referencePsychDay: anchor)
        let commitment = Commitment(
            title: "Run",
            slots: [],
            target: QuantifiedCycle(cycle: targetCycle, count: 3),
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

    @Test("grace cycle: isGrace is true when cycle overlaps a GracePeriod")
    @MainActor
    func graceCycleIsMarkedGrace() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let anchor = date(year: 2026, month: 3, day: 30)  // Monday
        let targetCycle = Cycle(kind: .weekly, referencePsychDay: anchor)
        let commitment = Commitment(
            title: "Run",
            slots: [],
            target: QuantifiedCycle(cycle: targetCycle, count: 3),
        )
        // Grace covers the week Mar 30 – Apr 6
        commitment.gracePeriods = [
            GracePeriod(
                startPsychDay: date(year: 2026, month: 3, day: 30),
                endPsychDay: date(year: 2026, month: 4, day: 6),
                reason: .creation
            )
        ]
        ctx.insert(commitment)

        let preReport = PreTokenReportBuilder.build(
            commitments: [commitment],
            startPsychDay: date(year: 2026, month: 3, day: 30),
            endPsychDay: date(year: 2026, month: 4, day: 6)
        )

        #expect(preReport.count == 1)
        let cycle = try #require(preReport.first?.cycles.first)
        #expect(cycle.isGrace == true)
    }

    @Test("non-grace cycle: isGrace is false when no GracePeriod overlaps")
    @MainActor
    func nonGraceCycleIsNotMarkedGrace() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let anchor = date(year: 2026, month: 3, day: 30)
        let targetCycle = Cycle(kind: .weekly, referencePsychDay: anchor)
        let commitment = Commitment(
            title: "Run",
            slots: [],
            target: QuantifiedCycle(cycle: targetCycle, count: 3),
        )
        // Grace only covers the prior week — no overlap with the report window
        commitment.gracePeriods = [
            GracePeriod(
                startPsychDay: date(year: 2026, month: 3, day: 23),
                endPsychDay: date(year: 2026, month: 3, day: 30),
                reason: .creation
            )
        ]
        ctx.insert(commitment)

        let preReport = PreTokenReportBuilder.build(
            commitments: [commitment],
            startPsychDay: date(year: 2026, month: 3, day: 30),
            endPsychDay: date(year: 2026, month: 4, day: 6)
        )

        #expect(preReport.count == 1)
        let cycle = try #require(preReport.first?.cycles.first)
        #expect(cycle.isGrace == false)
    }

    @Test("grace cycle: appears in report but receives no PT compensation")
    @MainActor
    func graceCycleReceivesNoPTCompensation() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let anchor = date(year: 2026, month: 3, day: 30)  // Monday
        let targetCycle = Cycle(kind: .weekly, referencePsychDay: anchor)
        let commitment = Commitment(
            title: "Run",
            slots: [],
            target: QuantifiedCycle(cycle: targetCycle, count: 3),
        )
        // 0 check-ins, grace covers the full week — should see no PT applied
        commitment.gracePeriods = [
            GracePeriod(
                startPsychDay: date(year: 2026, month: 3, day: 30),
                endPsychDay: date(year: 2026, month: 4, day: 6),
                reason: .creation
            )
        ]
        ctx.insert(commitment)

        let t1 = PositivityToken(reason: "a", createdAt: date(year: 2026, month: 1, day: 1))
        let t2 = PositivityToken(reason: "b", createdAt: date(year: 2026, month: 1, day: 2))
        ctx.insert(t1)
        ctx.insert(t2)

        let preReport = PreTokenReportBuilder.build(
            commitments: [commitment],
            startPsychDay: date(year: 2026, month: 3, day: 30),
            endPsychDay: date(year: 2026, month: 4, day: 6)
        )
        let report = AfterPositivityTokenReportBuilder.apply(
            to: preReport,
            allTokens: [t1, t2],
            monthlyCap: 10
        )

        #expect(report.count == 1)
        let cycle = try #require(report.first?.cycles.first)
        // Grace cycle must appear in the report
        #expect(cycle.isGrace == true)
        // No PT tokens consumed
        #expect(cycle.aidedByPositivityTokenCount == 0)
        // Tokens remain active
        #expect(t1.status == .active)
        #expect(t2.status == .active)
    }

    @Test("start >= end returns empty report")
    @MainActor
    func invalidDateRangeReturnsEmpty() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let anchor = date(year: 2026, month: 2, day: 1)
        let targetCycle = Cycle(kind: .daily, referencePsychDay: anchor)
        let commitment = Commitment(
            title: "Read",
            slots: [],
            target: QuantifiedCycle(cycle: targetCycle, count: 1),
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
