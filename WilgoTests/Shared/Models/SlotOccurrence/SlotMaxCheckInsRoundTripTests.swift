import Foundation
import SwiftData
import Testing
@testable import Wilgo

extension SlotOccurrenceSuite {
@Suite(.serialized)
final class SlotMaxCheckInsRoundTripTests {
    @Test("Slot persists nil maxCheckIns by default")
    @MainActor func defaultIsNil() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = Slot(start: timeOfDay(hour: 9), end: timeOfDay(hour: 11))
        ctx.insert(slot)
        try ctx.save()

        let fetched = try #require(ctx.fetch(FetchDescriptor<Slot>()).first)
        #expect(fetched.maxCheckIns == nil)
    }

    @Test("Slot round-trips an explicit maxCheckIns")
    @MainActor func roundTripsExplicitValue() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = Slot(start: timeOfDay(hour: 9), end: timeOfDay(hour: 11))
        slot.maxCheckIns = 1
        ctx.insert(slot)
        try ctx.save()

        let fetched = try #require(ctx.fetch(FetchDescriptor<Slot>()).first)
        #expect(fetched.maxCheckIns == 1)
    }
}
}
