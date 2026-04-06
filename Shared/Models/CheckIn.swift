import Foundation
import SwiftData

enum CheckInStatus: String, Codable {
    case completed
}

@Model
final class CheckIn {
    @Attribute(.unique)
    var id: UUID

    @Relationship var commitment: Commitment?

    var positivityToken: PositivityToken?

    /// NOTE: Currently not in use.
    var status: CheckInStatus = CheckInStatus.completed

    /// Absolute creation time (treated as UTC ground truth).
    var createdAt: Date

    /// Time zone identifier at creation time (e.g. "America/Los_Angeles").
    var timeZoneIdentifier: String = TimeZone.current.identifier

    /// Logical "psychological day" for this check-in, based on time zone and day-start rule.
    /// This is the local calendar day the user psychologically considers this check-in to belong to.
    var psychDay: Date = Date()

    init(
        commitment: Commitment,
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.commitment = commitment
        self.createdAt = createdAt

        let tzId = TimeZone.current.identifier
        self.timeZoneIdentifier = tzId
        self.psychDay = Time.psychDay(for: createdAt, timeZoneIdentifier: tzId)
    }
}
