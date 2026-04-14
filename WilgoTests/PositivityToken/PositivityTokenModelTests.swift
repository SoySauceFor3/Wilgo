import Foundation
import SwiftData
import Testing

@testable import Wilgo

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

@Suite("PositivityTokenModel")
@MainActor
struct PositivityTokenModelTests {

    /// A PositivityToken can be inserted into a SwiftData container without any linked check-in.
    @Test func insertTokenWithoutCheckIn() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let token = PositivityToken(reason: "I stayed consistent this week")
        ctx.insert(token)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<PositivityToken>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.reason == "I stayed consistent this week")
        #expect(fetched.first?.status == .active)
        #expect(fetched.first?.dayOfStatus == nil)
    }

    /// PositivityToken.init no longer accepts a checkIn parameter.
    /// Verify the default init produces a well-formed token.
    @Test func defaultInitValues() {
        let before = Date()
        let token = PositivityToken(reason: "growth mindset")
        let after = Date()

        #expect(token.reason == "growth mindset")
        #expect(token.status == .active)
        #expect(token.dayOfStatus == nil)
        #expect(token.createdAt >= before)
        #expect(token.createdAt <= after)
    }

    /// Multiple tokens can coexist in the store without any check-in linkage.
    @Test func multipleTokensInsertedSuccessfully() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let reasons = ["reason A", "reason B", "reason C"]
        for reason in reasons {
            ctx.insert(PositivityToken(reason: reason))
        }
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<PositivityToken>())
        #expect(fetched.count == 3)
        let fetchedReasons = Set(fetched.map(\.reason))
        #expect(fetchedReasons == Set(reasons))
    }

    /// A token with a custom createdAt date is stored correctly.
    @Test func customCreatedAt() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        var comps = DateComponents()
        comps.year = 2026
        comps.month = 1
        comps.day = 15
        let customDate = Calendar.current.date(from: comps)!

        let token = PositivityToken(reason: "retrospective token", createdAt: customDate)
        ctx.insert(token)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<PositivityToken>())
        #expect(fetched.first?.createdAt == customDate)
    }
}
