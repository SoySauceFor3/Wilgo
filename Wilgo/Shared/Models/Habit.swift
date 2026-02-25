//
//  Habit.swift
//  Wilgo
//
//  Created by Cursor AI on 2/25/26.
//

import Foundation
import SwiftData

enum ProofOfWorkType: String, Codable {
    case manual = "Manual"
    // case notionAPI = "Notion API"
    // case healthKit = "HealthKit"
}

enum Period: String, Codable {
    case daily   = "Daily"
    case weekly  = "Weekly"
    case monthly = "Monthly"
}

@Model
final class Habit {
    var title: String
    var createdAt: Date

    /// Historical completion / skip records for this habit.
    @Relationship(deleteRule: .cascade, inverse: \HabitCheckIn.habit)
    var checkIns: [HabitCheckIn] = []

    /// Whether this habit has been completed for the current check-in context.
    /// This is intentionally simple for now and can later be replaced with a
    /// proper per-day completion history.
    var isCompleted: Bool

    /// How often the habit must be completed (e.g. 3× per week)
    var frequencyCount: Int
    var frequencyPeriod: Period

    /// Start of the ideal completion window ("Golden Hours") represented as a `Date`
    /// on an arbitrary reference day, using only its time components.
    var idealWindowStart: Date

    /// End of the ideal completion window ("Golden Hours") represented as a `Date`
    /// on an arbitrary reference day, using only its time components.
    var idealWindowEnd: Date

    /// Number of allowed skips within the budget period
    var skipCreditCount: Int

    /// The period over which skipBudget resets
    var skipCreditPeriod: Period

    /// How completion is verified
    var proofOfWorkType: ProofOfWorkType

    init(
        title: String,
        createdAt: Date = .now,
        isCompleted: Bool = false,
        frequencyCount: Int,
        frequencyPeriod: Period,
        idealWindowStart: Date,
        idealWindowEnd: Date,
        skipCreditCount: Int,
        skipCreditPeriod: Period,
        proofOfWorkType: ProofOfWorkType = .manual
    ) {
        self.title = title
        self.createdAt = createdAt
        self.isCompleted = isCompleted
        self.frequencyCount = frequencyCount
        self.frequencyPeriod = frequencyPeriod
        self.idealWindowStart = idealWindowStart
        self.idealWindowEnd = idealWindowEnd
        self.skipCreditCount = skipCreditCount
        self.skipCreditPeriod = skipCreditPeriod
        self.proofOfWorkType = proofOfWorkType
    }
}

