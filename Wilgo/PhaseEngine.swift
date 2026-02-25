//
//  PhaseEngine.swift
//  Wilgo
//
//  Phase and pressure-spectrum logic for habits. Used by Stage view and (later) notifications.
//

import Foundation
import SwiftUI

/// Current phase of a habit in the pressure spectrum.
enum HabitPhase: String {
    case gentle     // Inside ideal window
    case judgmental // Past window, before critical period
    case critical   // Last stretch before soft deadline
    case settled    // Before window or after soft deadline (inactive for "current" focus)
}

/// UI attributes derived from phase for consistent styling across Stage and notifications.
struct PhaseStyle {
    let color: Color
    let toneMessage: String
    let urgency: Int // 0 = none, 1 = gentle, 2 = judgmental, 3 = critical

    static func forPhase(_ phase: HabitPhase) -> PhaseStyle {
        switch phase {
        case .gentle:
            return PhaseStyle(color: .green, toneMessage: "Now’s a great time.", urgency: 1)
        case .judgmental:
            return PhaseStyle(color: .orange, toneMessage: "Window’s closing. Still doable.", urgency: 2)
        case .critical:
            return PhaseStyle(color: .red, toneMessage: "Last call. Do it or burn a credit.", urgency: 3)
        case .settled:
            return PhaseStyle(color: .gray, toneMessage: "Not in window.", urgency: 0)
        }
    }
}

/// Soft-deadline and phase cutoffs. Can later come from app settings.
struct PhaseConfig {
    /// End of day used as soft deadline (e.g. midnight = 24:00 next day).
    var softDeadlineHour: Int
    var softDeadlineMinute: Int
    /// Hours before soft deadline when we switch to Critical.
    var criticalWindowHours: Double

    static let `default` = PhaseConfig(
        softDeadlineHour: 24,
        softDeadlineMinute: 0,
        criticalWindowHours: 2
    )
}

enum PhaseEngine {

    /// Returns the current phase for the habit at `now`, and the style to use in UI.
    static func phaseAndStyle(for habit: Habit, now: Date = Date()) -> (HabitPhase, PhaseStyle) {
        let phase = phase(for: habit, now: now)
        return (phase, PhaseStyle.forPhase(phase))
    }

    /// Returns the current phase for the habit at `now`.
    static func phase(for habit: Habit, now: Date = Date()) -> HabitPhase {
        let calendar = HabitScheduling.calendar
        let windowStart = HabitScheduling.windowStartToday(for: habit)
        let windowEnd = HabitScheduling.windowEndToday(for: habit)
        let softDeadline = HabitScheduling.softDeadline(for: habit, now: now)

        // Handle window that crosses midnight (e.g. 22:00–01:00)
        let windowEndsTomorrow = windowEnd <= windowStart
        let effectiveWindowEnd: Date
        if windowEndsTomorrow && now < windowStart {
            // Before window start: "yesterday's" end was earlier today
            effectiveWindowEnd = windowEnd
        } else if windowEndsTomorrow {
            effectiveWindowEnd = calendar.date(byAdding: .day, value: 1, to: windowEnd) ?? windowEnd
        } else {
            effectiveWindowEnd = windowEnd
        }

        if now < windowStart {
            return .settled
        }
        if now <= effectiveWindowEnd {
            return .gentle
        }
        let criticalStart = HabitScheduling.criticalStart(now: now)
        if now < criticalStart {
            return .judgmental
        }
        if now < softDeadline {
            return .critical
        }
        return .settled
    }
}
