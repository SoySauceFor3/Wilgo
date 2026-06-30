//
//  AppSettings.swift
//  Wilgo
//
//  UserDefaults key constants. Centralised here so non-SwiftUI code
//  (Time, WilgoApp) shares the same string as @AppStorage views.
//

import Foundation
import SwiftUI

enum AppSettings {
    /// Monthly cap for positivity token usage (instead of creation). Default: 5.
    static let positivityTokenMonthlyCapKey = "positivityTokenMonthlyCap"

    /// Last psych-day up to which the finished-cycle popup has been shown.
    static let finishedCycleReportLastShownPsychDayKey = "finishedCycleReportLastShownPsychDay"

    /// Whether the week starts on Monday (true) or Sunday (false). Default: true.
    static let weekStartsOnMondayKey = "weekStartsOnMonday"

    /// Reads the week-start preference from UserDefaults. Returns `true` (Monday) when the key is absent.
    static var weekStartsOnMonday: Bool {
        UserDefaults.standard.object(forKey: weekStartsOnMondayKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: weekStartsOnMondayKey)
    }

    /// The Calendar weekday integer for the configured week-start day (1 = Sunday, 2 = Monday).
    static var weekStartWeekday: Int { weekStartsOnMonday ? 2 : 1 }

    /// How many commitments appear in the Stage's "Upcoming" list. Default: 3, minimum 0.
    /// 0 is a valid choice — it hides the Upcoming section entirely.
    static let upcomingCommitmentCountKey = "upcomingCommitmentCount"

    /// Reads the Upcoming commitment count from UserDefaults. Returns 3 when absent;
    /// clamps to a minimum of 0 (0 = user wants no Upcoming; negative would be meaningless).
    static var upcomingCommitmentCount: Int {
        let raw = UserDefaults.standard.object(forKey: upcomingCommitmentCountKey) as? Int
        return max(0, raw ?? 3)
    }

    /// Whether catch-up reminders also fire for a behind commitment whose slot is open *right now*.
    /// Default: false (exclude) — an open-slot commitment is already maximally visible, so a push
    /// would be redundant. Users who want "remind whenever behind" can opt in.
    static let includeActiveSlotsInCatchUpReminderKey = "includeActiveSlotsInCatchUpReminder"

    /// Reads the include-active-slots preference. Returns `false` (exclude) when the key is absent.
    static var includeActiveSlotsInCatchUp: Bool {
        UserDefaults.standard.bool(forKey: includeActiveSlotsInCatchUpReminderKey)
    }
}

#if DEBUG
    // MARK: - Debug environment

    struct TriggerCycleReportKey: EnvironmentKey {
        static let defaultValue: () -> Void = {}
    }

    extension EnvironmentValues {
        var triggerCycleReport: () -> Void {
            get { self[TriggerCycleReportKey.self] }
            set { self[TriggerCycleReportKey.self] = newValue }
        }
    }
#endif
