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
    /// Hour (0–12) when the "commitment day" begins. Default: 0 (midnight).
    static let dayStartHourKey = "dayStartHour"

    /// Monthly cap for positivity token usage (instead of creation). Default: 5.
    static let positivityTokenMonthlyCapKey = "positivityTokenMonthlyCap"

    /// Last psych-day up to which the finished-cycle popup has been shown.
    static let finishedCycleReportLastShownPsychDayKey = "finishedCycleReportLastShownPsychDay"
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
