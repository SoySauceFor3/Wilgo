import Foundation
import SwiftData

@Model
final class PositivityToken {
    var id: UUID?
    var reason: String
    var createdAt: Date

    var status: Status
    /// Psych day when the token was used or expired; meaningless when `status == .active`.
    var dayOfStatus: Date?

    /// Set when minted so we enforce at most one token per check-in.
    @Relationship(deleteRule: .nullify, inverse: \CheckIn.positivityToken)
    var checkIn: CheckIn?

    enum Status: String, Codable {
        case active
        case used
        case expired
    }

    init(reason: String, createdAt: Date = .now, checkIn: CheckIn? = nil) {
        self.id = UUID()
        self.reason = reason
        self.createdAt = createdAt
        self.status = .active
        self.dayOfStatus = nil
        self.checkIn = checkIn

        // help the reverse propogation because otherwise it is pretty slow.
        checkIn?.positivityToken = self
    }
}
