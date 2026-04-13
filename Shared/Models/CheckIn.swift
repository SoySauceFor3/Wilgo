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

    /// NOTE: Currently not in use.
    var status: CheckInStatus = CheckInStatus.completed

    /// Absolute creation time (treated as UTC ground truth).
    var createdAt: Date

    /// Calendar day this check-in belongs to (midnight of the local day at creation time).
    var psychDay: Date = Date()

    init(
        commitment: Commitment,
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.commitment = commitment
        self.createdAt = createdAt

        self.psychDay = Time.startOfDay(for: createdAt)
    }
}
