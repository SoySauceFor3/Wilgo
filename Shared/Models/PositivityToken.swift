import Foundation
import SwiftData

@Model
final class PositivityToken {
    @Attribute(.unique)
    var id: UUID
    var reason: String
    var createdAt: Date

    /// The CycleRecord that consumed this token. Nil = free in the wins journal.
    @Relationship(deleteRule: .nullify)
    var consumedByCycleRecord: CycleRecord?

    init(reason: String, createdAt: Date = .now) {
        self.id = UUID()
        self.reason = reason
        self.createdAt = createdAt
        self.consumedByCycleRecord = nil
    }
}
