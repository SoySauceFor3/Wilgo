import Foundation
import SwiftData

enum CycleOutcome: String, Codable {
    case passed
    case excused
    case punished
    case letGo
    case other
}

@Model
final class CycleRecord {
    @Attribute(.unique)
    var id: UUID

    // Cascade — deleting a Commitment deletes all its CycleRecords
    @Relationship(deleteRule: .cascade)
    var commitment: Commitment

    // Snapshot of the commitment at the time of the cycle record
    var snapshotTitle: String
    var cycleStart: Date
    var cycleEnd: Date
    var targetCount: Int
    var checkInCount: Int
    var recordedAt: Date

    // Passed cycles only (empty if failed)
    var emojiReactions: [String]

    // Failed cycles only (nil if passed)
    var outcome: CycleOutcome?
    var reflectionText: String?

    // Nullify — if CycleRecord is deleted, PT is freed back to the journal
    @Relationship(deleteRule: .nullify, inverse: \PositivityToken.consumedByCycleRecord)
    var consumedPT: PositivityToken?

    init(
        commitment: Commitment,
        snapshotTitle: String,
        cycleStart: Date,
        cycleEnd: Date,
        targetCount: Int,
        checkInCount: Int,
        outcome: CycleOutcome?,
        reflectionText: String?,
        emojiReactions: [String],
        consumedPT: PositivityToken?,
        recordedAt: Date = .now
    ) {
        self.id = UUID()
        self.commitment = commitment
        self.snapshotTitle = snapshotTitle
        self.cycleStart = cycleStart
        self.cycleEnd = cycleEnd
        self.targetCount = targetCount
        self.checkInCount = checkInCount
        self.outcome = outcome
        self.reflectionText = reflectionText
        self.emojiReactions = emojiReactions
        self.consumedPT = consumedPT
        self.recordedAt = recordedAt
    }
}
