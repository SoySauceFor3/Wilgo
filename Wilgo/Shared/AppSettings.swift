//
//  AppSettings.swift
//  Wilgo
//
//  UserDefaults key constants. Centralised here so non-SwiftUI code
//  (CommitmentScheduling, WilgoApp) shares the same string as @AppStorage views.
//

import Foundation

enum AppSettings {
    /// Hour (0–12) when the "commitment day" begins. Default: 0 (midnight).
    static let dayStartHourKey = "dayStartHour"
}
