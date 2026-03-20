//
//  SettingsView.swift
//  Wilgo
//
//  App-wide settings. Currently: day-start hour configuration.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.dayStartHourKey)
    private var dayStartHour: Int = 0

    @AppStorage(AppSettings.positivityTokenMonthlyCapKey)
    private var positivityTokenMonthlyCap: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Day starts at", selection: $dayStartHour) {
                        ForEach(0..<24) { hour in
                            Text(hourLabel(hour)).tag(hour)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("Schedule")
                } footer: {
                    Text(
                        "Commitments are tracked from this hour until the same time the next day. The morning report notification also fires at this hour. Changes apply going forward — past check-ins are not affected."
                    )
                }

                // NEW: Section for Positivity Token Monthly Cap
                Section {
                    Picker(
                        "Monthly Positivity Token Cap",
                        selection: Binding(
                            get: {
                                // Only allow values 1...10, default to 5 if invalid or uninitialized
                                let v = positivityTokenMonthlyCap
                                return (1...10).contains(v) ? v : 5
                            },
                            set: { newVal in
                                // Clamp values just in case, and save
                                positivityTokenMonthlyCap = min(max(newVal, 1), 10)
                            }
                        )
                    ) {
                        ForEach(1...10, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                } header: {
                    Text("Positivity Tokens")
                } footer: {
                    Text(
                        "Maximum number of positivity tokens you can use per month. Default is 5."
                    )
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return "12:00 AM — Midnight"
        case 12: return "12:00 PM — Noon"
        default: return hour < 12 ? "\(hour):00 AM" : "\(hour - 12):00 PM"
        }
    }
}

#Preview {
    SettingsView()
}
