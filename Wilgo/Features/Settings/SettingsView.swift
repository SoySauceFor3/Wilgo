//
//  SettingsView.swift
//  Wilgo
//
//  App-wide settings. Currently: day-start hour configuration.
//

import SwiftUI

#if DEBUG
    import Supabase
#endif

struct SettingsView: View {
    @AppStorage(AppSettings.positivityTokenMonthlyCapKey)
    private var positivityTokenMonthlyCap: Int = 0

    #if DEBUG
        @Environment(\.triggerCycleReport) private var triggerCycleReport
        @State private var debugWatermarkDate: Date = Date()
        @State private var supabaseSpikeResult: String = ""
        @State private var supabaseSpikeRunning: Bool = false
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

                Section("Tags") {
                    NavigationLink("Tags", destination: TagsSettingsView())
                }

                #if DEBUG
                    // TODO: remove in Phase 1b cleanup. Phase 1a smoke spike — proves the
                    // iOS app can round-trip a row through Supabase. See documentation/Backend/01a-Spike.md.
                    Section {
                        Button(supabaseSpikeRunning ? "Running…" : "Spike: Insert + Read") {
                            runSupabaseSpike()
                        }
                        .disabled(supabaseSpikeRunning)
                        if !supabaseSpikeResult.isEmpty {
                            Text(supabaseSpikeResult)
                                .font(.caption)
                                .foregroundStyle(
                                    supabaseSpikeResult.hasPrefix("OK") ? .green : .red)
                        }
                    } header: {
                        Text("Debug — Supabase Spike (Phase 1a)")
                    } footer: {
                        Text(
                            "Inserts a row into commitments_spike, reads it back, then deletes it. Verifies the SDK + config wiring work end-to-end."
                        )
                    }

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

    #if DEBUG
        // TODO: remove in Phase 1b cleanup.
        private func runSupabaseSpike() {
            supabaseSpikeRunning = true
            supabaseSpikeResult = ""
            Task {
                do {
                    let id = UUID()
                    let title = "spike-\(Int(Date().timeIntervalSince1970))"

                    struct SpikeInsert: Encodable {
                        let id: UUID
                        let title: String
                    }
                    struct SpikeRow: Decodable {
                        let id: UUID
                        let title: String
                    }

                    try await Backend.client
                        .from("commitments_spike")
                        .insert(SpikeInsert(id: id, title: title))
                        .execute()

                    let read: SpikeRow = try await Backend.client
                        .from("commitments_spike")
                        .select()
                        .eq("id", value: id)
                        .single()
                        .execute()
                        .value

                    try await Backend.client
                        .from("commitments_spike")
                        .delete()
                        .eq("id", value: id)
                        .execute()

                    let ok = read.title == title
                    await MainActor.run {
                        supabaseSpikeResult =
                            ok ? "OK: round-trip succeeded (id=\(id))" : "FAIL: title mismatch"
                        supabaseSpikeRunning = false
                    }
                } catch {
                    await MainActor.run {
                        supabaseSpikeResult = "FAIL: \(error)"
                        supabaseSpikeRunning = false
                    }
                }
            }
        }
    #endif
}

#Preview {
    SettingsView()
}
