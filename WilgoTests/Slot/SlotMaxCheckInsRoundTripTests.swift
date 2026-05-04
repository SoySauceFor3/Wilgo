import Foundation
import SwiftData
import Testing

@testable import Wilgo

@Suite("Slot.maxCheckIns - SwiftData round-trip", .serialized)
final class SlotMaxCheckInsRoundTripTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Commitment.self, Slot.self, CheckIn.self,
            SlotSnooze.self, Tag.self, PositivityToken.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func tod(hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 1; c.hour = hour
        return Calendar.current.date(from: c)!
    }

    @Test("Slot persists nil maxCheckIns by default")
    @MainActor func defaultIsNil() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        ctx.insert(slot)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Slot>()).first!
        #expect(fetched.maxCheckIns == nil)
    }

    @Test("Slot round-trips an explicit maxCheckIns")
    @MainActor func roundTripsExplicitValue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        slot.maxCheckIns = 1
        ctx.insert(slot)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Slot>()).first!
        #expect(fetched.maxCheckIns == 1)
    }
}
