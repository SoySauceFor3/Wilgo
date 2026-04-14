import Foundation
import SwiftData

@Model final class Tag {
    @Attribute(.unique) var id: UUID
    var name: String
    var displayOrder: Int
    @Relationship(deleteRule: .nullify)
    var commitments: [Commitment] = []  // nullify: deleting a Commitment removes it from this array; Tag survives

    init(name: String, displayOrder: Int) {
        self.id = UUID()
        self.name = name
        self.displayOrder = displayOrder
    }
}
