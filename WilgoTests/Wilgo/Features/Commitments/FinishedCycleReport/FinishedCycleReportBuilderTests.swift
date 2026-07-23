import Foundation
import SwiftData
import Testing
@testable import Wilgo

extension FinishedCycleReportSuite {
@Suite
struct FinishedCycleReportBuilderTests: ~Copyable {
    @Test("build returns one cycle with correct check-in count")
    @MainActor
    func buildReturnsCycleWithCorrectCheckInCount() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let anchor = testDate(year: 2026, month: 2, day: 1)
        let commitment = Commitment(
            title: "Read",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [],
            target: Target(count: 5)
        )
        ctx.insert(commitment)

        for hour in [9, 10, 11] {
            let checkIn = CheckIn(
                commitment: commitment,
                createdAt: testDate(year: 2026, month: 2, day: 1, hour: hour)
            )
            ctx.insert(checkIn)
            commitment.checkIns.append(checkIn)
        }

        let report = CycleReportBuilder.build(
            commitments: [commitment],
            startPsychDay: testDate(year: 2026, month: 2, day: 1),
            endPsychDay: testDate(year: 2026, month: 2, day: 2)
        )

        #expect(report.count == 1)
        let cycle = try #require(report.first?.cycles.first)
        #expect(cycle.actualCheckIns == 3)
        #expect(cycle.targetCheckIns == 5)
        #expect(cycle.metTarget == false)
    }

    @Test("build returns met-target cycle when check-ins >= target")
    @MainActor
    func buildReturnsMetTargetWhenCheckInsAtTarget() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let anchor = testDate(year: 2026, month: 2, day: 1)
        let commitment = Commitment(
            title: "Run",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [],
            target: Target(count: 3)
        )
        ctx.insert(commitment)

        for hour in [9, 10, 11] {
            let checkIn = CheckIn(
                commitment: commitment,
                createdAt: testDate(year: 2026, month: 2, day: 1, hour: hour)
            )
            ctx.insert(checkIn)
            commitment.checkIns.append(checkIn)
        }

        let report = CycleReportBuilder.build(
            commitments: [commitment],
            startPsychDay: testDate(year: 2026, month: 2, day: 1),
            endPsychDay: testDate(year: 2026, month: 2, day: 2)
        )

        let cycle = try #require(report.first?.cycles.first)
        #expect(cycle.metTarget == true)
    }

    @Test("target disabled: effectiveTargetMode is disabled, count preserved")
    @MainActor
    func targetDisabled_reportPreservesCount() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let anchor = testDate(year: 2026, month: 2, day: 1)
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [],
            target: Target(count: 3, mode: .disabled)
        )
        ctx.insert(c)
        let checkIn = CheckIn(commitment: c, createdAt: testDate(year: 2026, month: 2, day: 1, hour: 9))
        ctx.insert(checkIn)
        c.checkIns.append(checkIn)

        let report = CycleReportBuilder.build(
            commitments: [c],
            startPsychDay: testDate(year: 2026, month: 2, day: 1),
            endPsychDay: testDate(year: 2026, month: 2, day: 2)
        )

        #expect(report.count == 1)
        let cycle = try #require(report.first?.cycles.first)
        #expect(cycle.actualCheckIns == 1)
        #expect(cycle.targetCheckIns == 3)
        #expect(cycle.effectiveTargetMode == .disabled)
    }

    @Test("start >= end returns empty report")
    @MainActor
    func invalidDateRangeReturnsEmpty() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let anchor = testDate(year: 2026, month: 2, day: 1)
        let commitment = Commitment(
            title: "Read",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [],
            target: Target(count: 1)
        )
        ctx.insert(commitment)

        let report = CycleReportBuilder.build(
            commitments: [commitment],
            startPsychDay: testDate(year: 2026, month: 2, day: 2),
            endPsychDay: testDate(year: 2026, month: 2, day: 1)
        )
        #expect(report.isEmpty)
    }
}
}
