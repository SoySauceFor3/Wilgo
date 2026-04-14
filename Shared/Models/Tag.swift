import Foundation
import SwiftData

@Model final class Tag {
    @Attribute(.unique) var id: UUID
    var name: String
    var displayOrder: Int
    var createdAt: Date
    @Relationship(deleteRule: .nullify)
    var commitments: [Commitment] = []  // nullify: deleting a Commitment removes it from this array; Tag survives

    init(name: String, displayOrder: Int, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.displayOrder = displayOrder
        self.createdAt = createdAt
    }
}
