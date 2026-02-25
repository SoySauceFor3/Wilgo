//
//  AddHabitView.swift
//  Wilgo
//
//  Created by Cursor AI on 2/25/26.
//

import SwiftUI
import SwiftData

struct AddHabitView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var frequencyCount: Int = 1
    @State private var frequencyPeriod: Period = .daily
    @State private var idealWindowStart: Date
    @State private var idealWindowEnd: Date
    @State private var skipCreditCount: Int = 1
    @State private var skipCreditPeriod: Period = .weekly
    @State private var proofOfWorkType: ProofOfWorkType = .manual

    init() {
        let calendar = Calendar.current
        let now = Date()

        let defaultStart = calendar.date(
            bySettingHour: 6,
            minute: 0,
            second: 0,
            of: now
        ) ?? now

        let defaultEnd = calendar.date(
            bySettingHour: 8,
            minute: 0,
            second: 0,
            of: now
        ) ?? now

        _idealWindowStart = State(initialValue: defaultStart)
        _idealWindowEnd = State(initialValue: defaultEnd)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Title", text: $title)

                    Picker("Frequency period", selection: $frequencyPeriod) {
                        ForEach([Period.daily, .weekly, .monthly], id: \.self) { period in
                            Text(period.rawValue)
                                .tag(period)
                        }
                    }

                    Stepper(value: $frequencyCount, in: 1...21) {
                        Text("Frequency: \(frequencyCount)× \(frequencyPeriod.rawValue.lowercased())")
                    }
                }

                Section("Golden window") {
                    DatePicker(
                        "Start",
                        selection: $idealWindowStart,
                        displayedComponents: .hourAndMinute
                    )

                    DatePicker(
                        "End",
                        selection: $idealWindowEnd,
                        displayedComponents: .hourAndMinute
                    )
                }

                Section("Skip credits") {
                    Picker("Reset period", selection: $skipCreditPeriod) {
                        ForEach([Period.daily, .weekly, .monthly], id: \.self) { period in
                            Text(period.rawValue)
                                .tag(period)
                        }
                    }

                    Stepper(value: $skipCreditCount, in: 0...30) {
                        Text("Skip credits: \(skipCreditCount)")
                    }
                }

                Section("Proof of work") {
                    Picker("Type", selection: $proofOfWorkType) {
                        Text(ProofOfWorkType.manual.rawValue)
                            .tag(ProofOfWorkType.manual)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveHabit()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveHabit() {
        let habit = Habit(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            frequencyCount: frequencyCount,
            frequencyPeriod: frequencyPeriod,
            idealWindowStart: idealWindowStart,
            idealWindowEnd: idealWindowEnd,
            skipCreditCount: skipCreditCount,
            skipCreditPeriod: skipCreditPeriod,
            proofOfWorkType: proofOfWorkType
        )

        modelContext.insert(habit)
        dismiss()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Habit.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    return AddHabitView()
        .modelContainer(container)
}

