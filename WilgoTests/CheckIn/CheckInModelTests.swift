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

@MainActor
private func createTestCommitment(ctx: ModelContext) -> Commitment {
    let anchor = Date()
    let cycle = Cycle(kind: .daily, referencePsychDay: anchor)
    let commitment = Commitment(
        title: "Test Commitment",
        cycle: cycle,
        slots: [],
        target: QuantifiedCycle(count: 1)
    )
    ctx.insert(commitment)
    return commitment
}

@Suite("CheckInModel")
@MainActor
struct CheckInModelTests {

    /// A CheckIn inserted without specifying a source defaults to .app.
    @Test func defaultSourceIsApp() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let commitment = createTestCommitment(ctx: ctx)

        let checkIn = CheckIn(commitment: commitment)
        ctx.insert(checkIn)
        commitment.checkIns.append(checkIn)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<CheckIn>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.source == .app)
    }

    /// A CheckIn can be created with an explicit source, and it is stored correctly.
    @Test func explicitSourceIsStored() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let commitment = createTestCommitment(ctx: ctx)

        let checkIn = CheckIn(commitment: commitment, source: .widget)
        ctx.insert(checkIn)
        commitment.checkIns.append(checkIn)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<CheckIn>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.source == .widget)
    }

    /// CheckInSource enum values can be round-tripped through their rawValue.
    @Test func checkInSourceCodable() {
        let sources: [CheckInSource] = [.app, .widget, .liveActivity, .backfill]

        for source in sources {
            let rawValue = source.rawValue
            let decoded = CheckInSource(rawValue: rawValue)
            #expect(decoded == source)
        }
    }

    /// All CheckInSource values have non-empty raw values.
    @Test func checkInSourceRawValues() {
        #expect(!CheckInSource.app.rawValue.isEmpty)
        #expect(!CheckInSource.widget.rawValue.isEmpty)
        #expect(!CheckInSource.liveActivity.rawValue.isEmpty)
        #expect(!CheckInSource.backfill.rawValue.isEmpty)
    }

    /// Multiple CheckIn objects with different sources can coexist.
    @Test func multipleCheckInsWithDifferentSources() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let commitment = createTestCommitment(ctx: ctx)

        let sources: [CheckInSource] = [.app, .widget, .liveActivity, .backfill]
        for source in sources {
            let checkIn = CheckIn(commitment: commitment, source: source)
            ctx.insert(checkIn)
            commitment.checkIns.append(checkIn)
        }
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<CheckIn>())
        #expect(fetched.count == 4)

        let fetchedSources = Set(fetched.map(\.source))
        #expect(fetchedSources == Set(sources))
    }
}

// MARK: - CheckInIntent source decoding contract
//
// CheckInIntent (WidgetExtension target) is not importable from WilgoTests, so we verify
// the source-decoding contract it relies on: `CheckInSource(rawValue: sourceRaw) ?? .widget`.

@Suite("CheckInIntentSourceDecoding")
struct CheckInIntentSourceDecodingTests {

    /// sourceRaw "widget" decodes to .widget (normal widget button path).
    @Test func widgetRawValueDecodesToWidget() {
        let source = CheckInSource(rawValue: "widget") ?? .widget
        #expect(source == .widget)
    }

    /// sourceRaw "liveActivity" decodes to .liveActivity (Live Activity button path).
    @Test func liveActivityRawValueDecodesToLiveActivity() {
        let source = CheckInSource(rawValue: "liveActivity") ?? .widget
        #expect(source == .liveActivity)
    }

    /// An invalid sourceRaw falls back to .widget (defensive default in CheckInIntent.perform()).
    @Test func invalidRawValueFallsBackToWidget() {
        let source = CheckInSource(rawValue: "invalid_garbage") ?? .widget
        #expect(source == .widget)
    }

    /// Empty sourceRaw also falls back to .widget.
    @Test func emptyRawValueFallsBackToWidget() {
        let source = CheckInSource(rawValue: "") ?? .widget
        #expect(source == .widget)
    }
}
