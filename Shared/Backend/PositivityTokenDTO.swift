import Foundation

/// Wire-format mirror of `PositivityToken` for Supabase round-trips. SwiftData `@Model`
/// types are not directly Codable-friendly (inverse relationships, observers), so we
/// keep a parallel transport struct.
struct PositivityTokenDTO: Codable, Equatable {
    let id: UUID
    let userId: UUID
    let reason: String
    let createdAt: Date
    let status: String
    let dayOfStatus: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case reason
        case createdAt = "created_at"
        case status
        case dayOfStatus = "day_of_status"
    }
}

extension PositivityTokenDTO {
    init(_ model: PositivityToken, userId: UUID) {
        self.id = model.id
        self.userId = userId
        self.reason = model.reason
        self.createdAt = model.createdAt
        self.status = model.status.rawValue
        self.dayOfStatus = model.dayOfStatus
    }

    /// Mutates `model` in place to match this DTO. Caller owns the model and its context.
    func apply(to model: PositivityToken) {
        model.reason = reason
        model.createdAt = createdAt
        model.status = PositivityToken.Status(rawValue: status) ?? .active
        model.dayOfStatus = dayOfStatus
    }
}
