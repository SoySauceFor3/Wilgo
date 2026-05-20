//
//  SettingsView.swift
//  Wilgo
//
//  App-wide settings. Currently: day-start hour configuration.
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.positivityTokenMonthlyCapKey)
    private var positivityTokenMonthlyCap: Int = 0

    @AppStorage(AppSettings.weekStartsOnMondayKey)
    private var weekStartsOnMonday: Bool = true

    @Environment(\.modelContext) private var modelContext

    @State private var pendingWeekStart: Bool? = nil
    @State private var showWeekStartSheet = false

    #if DEBUG
        @Environment(\.triggerCycleReport) private var triggerCycleReport
        @State private var debugWatermarkDate: Date = .init()
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

                Section {
                    Picker("Week starts on", selection: Binding(
                        get: { weekStartsOnMonday },
                        set: { newValue in
                            guard newValue != weekStartsOnMonday else { return }
                            let all = (try? modelContext.fetch(FetchDescriptor<Commitment>())) ?? []
                            let affected = WeekStartChangeHandler.affectedCommitments(all, newStartsOnMonday: newValue)
                            if affected.isEmpty {
                                weekStartsOnMonday = newValue
                                CycleEndNotificationScheduler.refresh()
                            } else {
                                pendingWeekStart = newValue
                                showWeekStartSheet = true
                            }
                        }
                    )) {
                        Text("Monday").tag(true)
                        Text("Sunday").tag(false)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("Sets the first day of the week for new weekly commitments and the weekly heatmap view.")
                }

                Section("Tags") {
                    NavigationLink("Tags", destination: TagsSettingsView())
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
            .sheet(isPresented: $showWeekStartSheet) {
                weekStartSheet
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

    private var pendingCycleStart: Date {
        guard let pending = pendingWeekStart else { return Time.now() }
        return WeekStartChangeHandler.newCurrentCycleStart(newStartsOnMonday: pending)
    }

    private var pendingCycleEnd: Date {
        guard let pending = pendingWeekStart else { return Time.now() }
        return WeekStartChangeHandler.newCurrentCycleEnd(newStartsOnMonday: pending)
    }

    private func dateRangeLabel(start: Date, end: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let cal = Time.calendar
        let inclusiveEnd = cal.date(byAdding: .day, value: -1, to: end) ?? end
        return "\(fmt.string(from: start)) – \(fmt.string(from: inclusiveEnd))"
    }

    @ViewBuilder
    private var weekStartSheet: some View {
        let pending = pendingWeekStart!
        let affected = WeekStartChangeHandler.affectedCommitments(
            (try? modelContext.fetch(FetchDescriptor<Commitment>())) ?? [],
            newStartsOnMonday: pending
        )
        let start = pendingCycleStart
        let end = pendingCycleEnd

        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(
                    "Make the current cycle (\(dateRangeLabel(start: start, end: end))) inspiration only?"
                )
                .font(.body)

                if !affected.isEmpty {
                    Text("Affected commitments:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(affected) { c in
                        Text("• \(c.title)")
                            .font(.subheadline)
                    }
                }

                Spacer()

                VStack(spacing: 12) {
                    Button("Yes — make it inspiration only") {
                        applyWeekStartChange(inspirationOnly: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)

                    Button("No — just switch") {
                        applyWeekStartChange(inspirationOnly: false)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .navigationTitle("Week Start Change")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        pendingWeekStart = nil
                        showWeekStartSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func applyWeekStartChange(inspirationOnly: Bool) {
        guard let newValue = pendingWeekStart else { return }
        let all = (try? modelContext.fetch(FetchDescriptor<Commitment>())) ?? []
        let affected = WeekStartChangeHandler.affectedCommitments(all, newStartsOnMonday: newValue)
        WeekStartChangeHandler.apply(
            to: affected,
            newStartsOnMonday: newValue,
            makeCurrentCycleInspirationOnly: inspirationOnly
        )
        weekStartsOnMonday = newValue
        pendingWeekStart = nil
        showWeekStartSheet = false
        CycleEndNotificationScheduler.refresh()
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
