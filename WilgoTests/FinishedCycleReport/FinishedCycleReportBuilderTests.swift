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
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

@Suite("FinishedCycleReportBuilder", .serialized)
struct FinishedCycleReportBuilderTests: ~Copyable {
    private let savedOffset = UserDefaults.standard.integer(forKey: AppSettings.dayStartHourKey)

    init() {
        UserDefaults.standard.set(0, forKey: AppSettings.dayStartHourKey)
    }

    deinit {
        UserDefaults.standard.set(savedOffset, forKey: AppSettings.dayStartHourKey)
    }

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
            skipBudget: QuantifiedCycle(cycle: targetCycle, count: 0)
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
            skipBudget: QuantifiedCycle(cycle: targetCycle, count: 0)
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
            skipBudget: QuantifiedCycle(cycle: targetCycle, count: 0)
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
