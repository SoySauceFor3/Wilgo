import Foundation
import SwiftData
import WidgetKit

protocol CheckInEnqueuing {
    func enqueue(checkIn: CheckIn, title: String, context: ModelContext)
}

enum CheckInStatus: String, Codable {
    case completed
}

enum CheckInSource: String, Codable {
    case app          // normal in-app tap — no label shown
    case widget       // interactive widget button
    case liveActivity // Live Activity / lock screen button
    case backfill     // BackfillSheet
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

    /// Source of the check-in (app, widget, live activity, or backfill).
    var source: CheckInSource = CheckInSource.app

    init(
        commitment: Commitment,
        createdAt: Date = .now,
        source: CheckInSource = .app
    ) {
        self.id = UUID()
        self.commitment = commitment
        self.createdAt = createdAt
        self.source = source

        self.psychDay = Time.startOfDay(for: createdAt)
    }

    static func insert(
        commitment: Commitment,
        createdAt: Date = .now,
        source: CheckInSource = .app,
        title: String = "Check-in saved",
        into context: ModelContext,
        undoManager: (any CheckInEnqueuing)? = nil
    ) {
        let checkIn = CheckIn(commitment: commitment, createdAt: createdAt, source: source)
        context.insert(checkIn)
        commitment.checkIns.append(checkIn)
        WidgetCenter.shared.reloadTimelines(ofKind: WilgoConstants.currentCommitmentWidgetKind)
        undoManager?.enqueue(checkIn: checkIn, title: title, context: context)
    }

    static func delete(_ checkIn: CheckIn, from context: ModelContext) {
        context.delete(checkIn)
        WidgetCenter.shared.reloadTimelines(ofKind: WilgoConstants.currentCommitmentWidgetKind)
    }
}
