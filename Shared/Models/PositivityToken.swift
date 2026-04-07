import Foundation
import SwiftData

@Model
final class PositivityToken {
    @Attribute(.unique)
    var id: UUID
    var reason: String
    var createdAt: Date

    var status: Status
    /// Psych day when the token was used or expired; meaningless when `status == .active`.
    var dayOfStatus: Date?

    enum Status: String, Codable {
        case active
        case used
        case expired
    }

    init(reason: String, createdAt: Date = .now) {
        self.id = UUID()
        self.reason = reason
        self.createdAt = createdAt
        self.status = .active
        self.dayOfStatus = nil
    }
}
