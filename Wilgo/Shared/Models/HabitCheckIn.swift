//
//  HabitCheckIn.swift
//  Wilgo
//
//

import Foundation
import SwiftData

enum HabitCheckInStatus: String, Codable {
    case completed
}

@Model
final class HabitCheckIn {
    @Relationship var habit: Habit?

    /// Whether the habit was completed or intentionally skipped.
    var status: HabitCheckInStatus = HabitCheckInStatus.completed

    /// Absolute creation time (treated as UTC ground truth).
    var createdAt: Date

    /// Time zone identifier at creation time (e.g. "America/Los_Angeles").
    var timeZoneIdentifier: String = TimeZone.current.identifier

    /// Logical "psychological day" for this check-in, based on time zone and day-start rule.
    /// This is the local calendar day the user psychologically considers this check-in to belong to.
    var psychDay: Date = Date()

    init(
        habit: Habit,
        createdAt: Date = .now
    ) {
        self.habit = habit
        self.createdAt = createdAt

        let tzId = TimeZone.current.identifier
        self.timeZoneIdentifier = tzId
        self.psychDay = HabitScheduling.psychDay(for: createdAt, timeZoneIdentifier: tzId)
    }
}
