import Foundation
import SwiftData

extension Commitment {
    /// Shared predicate for excluding archived commitments. Used by both
    /// `@Query` sites (which require an inline predicate value) and
    /// `FetchDescriptor.activeOnly` (for imperative fetches).
    static var activePredicate: Predicate<Commitment> {
        #Predicate<Commitment> { $0.archivedAt == nil }
    }
}

extension FetchDescriptor where T == Commitment {
    static var activeOnly: FetchDescriptor<Commitment> {
        FetchDescriptor<Commitment>(predicate: Commitment.activePredicate)
    }
}
