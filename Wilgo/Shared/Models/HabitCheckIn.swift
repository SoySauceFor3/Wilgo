//
//  HabitCheckIn.swift
//  Wilgo
//
//

import Foundation
import SwiftData

enum HabitCheckInStatus: String, Codable {
    case completed
    case skipped  // TODO: Going to remove it as this should belonged to a different entity.
}

@Model
final class HabitCheckIn {
    @Relationship var habit: Habit?

    /// Whether the habit was completed or intentionally skipped.
    var status: HabitCheckInStatus

    /// Absolute creation time (treated as UTC ground truth).
    var createdAt: Date

    /// Time zone identifier at creation time (e.g. "America/Los_Angeles").
    var timeZoneIdentifier: String = TimeZone.current.identifier

    /// Logical "pyschological day" for this check-in, based on time zone and day-start rule.
    /// This is the local calendar day the user psychologically considers this check-in to belong to.
    var pyschDay: Date = Date()

    init(
        habit: Habit,
        status: HabitCheckInStatus,
        createdAt: Date = .now
    ) {
        self.habit = habit
        self.status = status
        self.createdAt = createdAt

        // Capture context for later streak / "which day" logic.
        let tzId = TimeZone.current.identifier
        self.timeZoneIdentifier = tzId
        self.pyschDay = HabitScheduling.psychDay(for: createdAt, timeZoneIdentifier: tzId)
    }
}
