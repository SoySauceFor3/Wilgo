//
//  AppSettings.swift
//  Wilgo
//
//  UserDefaults key constants. Centralised here so non-SwiftUI code
//  (Time, WilgoApp) shares the same string as @AppStorage views.
//

import Foundation

enum AppSettings {
    /// Hour (0–12) when the "commitment day" begins. Default: 0 (midnight).
    static let dayStartHourKey = "dayStartHour"

    /// Monthly cap for positivity token usage (instead of creation). Default: 5.
    static let positivityTokenMonthlyCapKey = "positivityTokenMonthlyCap"

    /// Last psych-day up to which the finished-cycle popup has been shown.
    static let finishedCycleReportLastShownPsychDayKey = "finishedCycleReportLastShownPsychDay"
}
