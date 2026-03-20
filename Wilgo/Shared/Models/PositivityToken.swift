import Foundation
import SwiftData

@Model
final class PositivityToken {
    var reason: String
    var createdAt: Date
    var status: Status

    enum Status: Codable {
        case active
        case used(Date)  // Date is the psych day of when the token was used, a token is used at the last day (inclusive) of the cycle.
        case expired(Date)  // Currently not supported.

        private enum CodingKeys: String, CodingKey { case type, date }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .type) {
            case "used":
                self = .used(try c.decode(Date.self, forKey: .date))
            case "expired":
                self = .expired(try c.decode(Date.self, forKey: .date))
            default:
                self = .active
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .active:
                try c.encode("active", forKey: .type)
            case .used(let date):
                try c.encode("used", forKey: .type)
                try c.encode(date, forKey: .date)
            case .expired(let date):
                try c.encode("expired", forKey: .type)
                try c.encode(date, forKey: .date)
            }
        }
    }

    init(reason: String, createdAt: Date = .now) {
        self.reason = reason
        self.createdAt = createdAt
        self.status = .active
    }
}
