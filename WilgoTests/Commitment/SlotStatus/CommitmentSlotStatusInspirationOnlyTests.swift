import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite(.serialized)
final class CommitmentSlotStatusInspirationOnlyTests {
    private func tod(hour: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2000
        comps.month = 1
        comps.day = 1
        comps.hour = hour
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps)!
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps)!
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, SlotSnooze.self, Tag.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    @Test("inspirationOnly active period → slotStatus .insideSlot; behindCount matches leftToDo")
    @MainActor func inspirationOnlyActive_insideSlot_behindCountCorrect() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        let commitment = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 5, day: 1)),
            slots: [slot],
            target: Target(
                count: 2,
                mode: .inspirationOnly(
                    start: date(year: 2026, month: 5, day: 7),
                    until: date(year: 2026, month: 5, day: 8)
                )
            )
        )
        ctx.insert(commitment)
        ctx.insert(slot)

        let now = date(year: 2026, month: 5, day: 7, hour: 10)
        let slotSt = commitment.slotStatus(now: now)
        let progress = commitment.goalProgress(now: now)
        let behindCount = progress.leftToDo.map { max(0, $0 - slotSt.remainingSlots.count) }

        #expect(slotSt.kind == .insideSlot)
        #expect(behindCount == 1)
    }

    @Test("inspirationOnly expired → behaves as .on; goalProgress.isMet when check-ins meet target")
    @MainActor func inspirationOnlyExpired_behavesAsOn_goalIsMet() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 15), end: tod(hour: 17))
        let commitment = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 5, day: 1)),
            slots: [slot],
            target: Target(
                count: 1,
                mode: .inspirationOnly(
                    start: date(year: 2026, month: 5, day: 6),
                    until: date(year: 2026, month: 5, day: 7)
                )
            )
        )
        let checkIn = CheckIn(commitment: commitment, createdAt: date(year: 2026, month: 5, day: 7, hour: 10))
        ctx.insert(commitment)
        ctx.insert(slot)
        ctx.insert(checkIn)
        commitment.checkIns = [checkIn]

        #expect(commitment.goalProgress(now: date(year: 2026, month: 5, day: 7, hour: 12)).isMet)
    }
}
