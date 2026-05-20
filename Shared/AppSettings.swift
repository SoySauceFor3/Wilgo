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
