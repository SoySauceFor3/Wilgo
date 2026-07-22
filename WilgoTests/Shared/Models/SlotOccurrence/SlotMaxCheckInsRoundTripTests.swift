import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite(.serialized)
final class SlotMaxCheckInsRoundTripTests {
    private func tod(hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2000
        c.month = 1
        c.day = 1
        c.hour = hour
        return Calendar.current.date(from: c)!
    }

    @Test("Slot persists nil maxCheckIns by default")
    @MainActor func defaultIsNil() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        ctx.insert(slot)
        try ctx.save()

        let fetched = try #require(ctx.fetch(FetchDescriptor<Slot>()).first)
        #expect(fetched.maxCheckIns == nil)
    }

    @Test("Slot round-trips an explicit maxCheckIns")
    @MainActor func roundTripsExplicitValue() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        slot.maxCheckIns = 1
        ctx.insert(slot)
        try ctx.save()

        let fetched = try #require(ctx.fetch(FetchDescriptor<Slot>()).first)
        #expect(fetched.maxCheckIns == 1)
    }
}
