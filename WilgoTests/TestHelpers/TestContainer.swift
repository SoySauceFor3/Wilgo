import Foundation
import SwiftData
@testable import Wilgo

/// Shared in-memory SwiftData container for all tests.
/// Add new models here — no need to update individual test files.
@MainActor
func makeTestContainer() throws -> ModelContainer {
    let schema = Schema([
        Commitment.self,
        Slot.self,
        CheckIn.self,
        PositivityToken.self,
        SlotSnooze.self,
        Tag.self,
        CycleRecord.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}
