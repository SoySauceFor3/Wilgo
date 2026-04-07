import Foundation
import SwiftData
import Testing

@testable import Wilgo

// MARK: - Helpers

private func date(year: Int, month: Int, day: Int) -> Date {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = 0
    comps.minute = 0
    comps.second = 0
    return Calendar.current.date(from: comps)!
}

/// Callers must keep the returned container alive for the entire test — `ModelContext` only
/// weakly references its `ModelContainer`; releasing the container makes subsequent operations crash.
@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema([Commitment.self, Slot.self, CheckIn.self, PositivityToken.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

private func makeCommitment() -> Commitment {
    let anchor = date(year: 2026, month: 3, day: 30)
    let cycle = Cycle(kind: .weekly, referencePsychDay: anchor)
    return Commitment(
        title: "Test",
        slots: [],
        target: QuantifiedCycle(cycle: cycle, count: 1),
    )
}

// MARK: - Schema / persistence tests (migration verification)
@Suite("GracePeriod", .serialized)
struct GracePeriodTests {
    @Suite("GracePeriod — SwiftData persistence", .serialized)
    struct GracePeriodPersistenceTests {

        @Test("new Commitment has empty gracePeriods by default")
        @MainActor
        func defaultGracePeriodsIsEmpty() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment()
            ctx.insert(commitment)
            try ctx.save()

            let fetched = try ctx.fetch(FetchDescriptor<Commitment>())
            #expect(fetched.count == 1)
            #expect(fetched[0].gracePeriods.isEmpty)
        }

        @Test("gracePeriods round-trips through save/fetch")
        @MainActor
        func gracePeriodsRoundTrip() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment()
            ctx.insert(commitment)

            let graceStart = date(year: 2026, month: 3, day: 30)
            let graceEnd = date(year: 2026, month: 4, day: 6)
            commitment.gracePeriods.append(
                GracePeriod(startPsychDay: graceStart, endPsychDay: graceEnd, reason: .creation)
            )
            try ctx.save()

            let fetched = try ctx.fetch(FetchDescriptor<Commitment>())
            #expect(fetched.count == 1)
            let gp = try #require(fetched[0].gracePeriods.first)
            #expect(gp.reason == .creation)
            #expect(gp.startPsychDay == graceStart)
            #expect(gp.endPsychDay == graceEnd)
        }

        @Test("multiple gracePeriods are all persisted")
        @MainActor
        func multipleGracePeriodsArePersisted() throws {
            let container = try makeContainer()
            let ctx = container.mainContext
            let commitment = makeCommitment()
            ctx.insert(commitment)

            commitment.gracePeriods = [
                GracePeriod(
                    startPsychDay: date(year: 2026, month: 3, day: 30),
                    endPsychDay: date(year: 2026, month: 4, day: 6),
                    reason: .creation
                ),
                GracePeriod(
                    startPsychDay: date(year: 2026, month: 4, day: 6),
                    endPsychDay: date(year: 2026, month: 4, day: 13),
                    reason: .ruleChange
                ),
            ]
            try ctx.save()

            let fetched = try ctx.fetch(FetchDescriptor<Commitment>())
            #expect(fetched[0].gracePeriods.count == 2)
        }
    }

    // MARK: - GracePeriod.overlaps logic tests

    @Suite("GracePeriod — overlaps()")
    struct GracePeriodOverlapTests {

        // Grace window: Mar 30 – Apr 6 (exclusive), i.e. the week of Mar 30–Apr 5.
        private let grace = GracePeriod(
            startPsychDay: date(year: 2026, month: 3, day: 30),
            endPsychDay: date(year: 2026, month: 4, day: 6),
            reason: .creation
        )

        @Test("exact cycle match overlaps")
        func exactMatch() {
            #expect(
                grace.overlaps(
                    cycleStart: date(year: 2026, month: 3, day: 30),
                    cycleEnd: date(year: 2026, month: 4, day: 6)
                ))
        }

        @Test("cycle entirely before grace does not overlap")
        func cycleBeforeGrace() {
            #expect(
                !grace.overlaps(
                    cycleStart: date(year: 2026, month: 3, day: 23),
                    cycleEnd: date(year: 2026, month: 3, day: 30)  // ends exactly at grace start
                ))
        }

        @Test("cycle entirely after grace does not overlap")
        func cycleAfterGrace() {
            #expect(
                !grace.overlaps(
                    cycleStart: date(year: 2026, month: 4, day: 6),  // starts exactly at grace end
                    cycleEnd: date(year: 2026, month: 4, day: 13)
                ))
        }

        @Test("cycle partially overlapping from before overlaps")
        func cycleStartsBeforeGrace() {
            #expect(
                grace.overlaps(
                    cycleStart: date(year: 2026, month: 3, day: 23),
                    cycleEnd: date(year: 2026, month: 4, day: 1)
                ))
        }

        @Test("cycle partially overlapping from after overlaps")
        func cycleEndsAfterGrace() {
            #expect(
                grace.overlaps(
                    cycleStart: date(year: 2026, month: 4, day: 1),
                    cycleEnd: date(year: 2026, month: 4, day: 13)
                ))
        }

        @Test("multi-cycle grace overlaps all cycles in range")
        func multiCycleGrace() {
            // Simulates vacation: grace covers Jan 15 – Feb 3.
            let vacationGrace = GracePeriod(
                startPsychDay: date(year: 2026, month: 1, day: 15),
                endPsychDay: date(year: 2026, month: 2, day: 3),
                reason: .disabled
            )
            // Week of Jan 13–19 overlaps (grace starts Jan 15, inside this cycle).
            #expect(
                vacationGrace.overlaps(
                    cycleStart: date(year: 2026, month: 1, day: 13),
                    cycleEnd: date(year: 2026, month: 1, day: 20)
                ))
            // Week of Jan 20–26 overlaps (entirely within grace).
            #expect(
                vacationGrace.overlaps(
                    cycleStart: date(year: 2026, month: 1, day: 20),
                    cycleEnd: date(year: 2026, month: 1, day: 27)
                ))
            // Week of Jan 27–Feb 2 overlaps (entirely within grace).
            #expect(
                vacationGrace.overlaps(
                    cycleStart: date(year: 2026, month: 1, day: 27),
                    cycleEnd: date(year: 2026, month: 2, day: 3)
                ))
            // Week of Feb 3–9 does NOT overlap (grace ends Feb 3, exclusive).
            #expect(
                !vacationGrace.overlaps(
                    cycleStart: date(year: 2026, month: 2, day: 3),
                    cycleEnd: date(year: 2026, month: 2, day: 10)
                ))
        }
    }
}
