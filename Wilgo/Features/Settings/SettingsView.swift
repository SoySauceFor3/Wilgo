//
//  SettingsView.swift
//  Wilgo
//
//  App-wide settings. Currently: day-start hour configuration.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.positivityTokenMonthlyCapKey)
    private var positivityTokenMonthlyCap: Int = 0

    #if DEBUG
        @Environment(\.triggerCycleReport) private var triggerCycleReport
        @State private var debugWatermarkDate: Date = Date()
    #endif

    var body: some View {
        NavigationStack {
            Form {
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

                #if DEBUG
                    Section {
                        DatePicker(
                            "Watermark date",
                            selection: $debugWatermarkDate,
                            displayedComponents: [.date]
                        )
                        Button("Set watermark & trigger report") {
                            UserDefaults.standard.set(
                                debugWatermarkDate.timeIntervalSinceReferenceDate,
                                forKey: AppSettings.finishedCycleReportLastShownPsychDayKey
                            )
                            triggerCycleReport()
                        }
                        Button("Reset watermark (first-launch state)") {
                            UserDefaults.standard.set(
                                0,
                                forKey: AppSettings.finishedCycleReportLastShownPsychDayKey
                            )
                        }
                    } header: {
                        Text("Debug — Cycle Report")
                    } footer: {
                        Text(
                            "Pick a past date and tap \"Set & trigger\" to simulate the report appearing as if you last saw it on that date. Only visible in debug builds."
                        )
                    }
                #endif
            }
            .navigationTitle("Settings")
            #if DEBUG
                .onAppear {
                    let stored = UserDefaults.standard.double(
                        forKey: AppSettings.finishedCycleReportLastShownPsychDayKey
                    )
                    if stored != 0 {
                        debugWatermarkDate = Date(timeIntervalSinceReferenceDate: stored)
                    }
                }
            #endif
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
