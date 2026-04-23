import SwiftUI

// MARK: - Reminder windows section (used by commitment form)

struct ReminderWindowsSection: View {
    @Binding var slotWindows: [SlotDraft]

    var body: some View {
        ForEach($slotWindows) { $window in
            SlotWindowRow(
                window: $window
            ) {
                slotWindows.removeAll { $0.id == window.id }
            }
        }

        Button {
            let (defaultStart, defaultEnd) = defaultWindowForNewSlot()
            slotWindows.append(SlotDraft(start: defaultStart, end: defaultEnd))
        } label: {
            Label("Add window", systemImage: "plus")
        }
    }

    static func defaultFirstWindow() -> (start: Date, end: Date) {
        let now = Date()
        let end = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
        return (start: now, end: end)
    }

    private func defaultWindowForNewSlot() -> (start: Date, end: Date) {
        if slotWindows.isEmpty {
            return Self.defaultFirstWindow()
        }

        let last = slotWindows[slotWindows.count - 1]
        return (last.start, last.end)
    }
}

// MARK: - SlotDraft (shared value type)

struct SlotDraft: Identifiable {
    let id = UUID()
    var start: Date
    var end: Date
    var recurrence: SlotRecurrence = .everyDay
}

// MARK: - SlotWindowRow (per-slot UI, including recurrence)

struct SlotWindowRow: View {
    @Binding var window: SlotDraft
    var onDelete: () -> Void

    private var crossesMidnight: Bool { window.end < window.start }
    @State private var showingRecurrenceEditor = false
    private var showsRepeatWarning: Bool {
        !window.recurrence.isValidSelection && window.recurrence.kindChoice != .everyDay
    }

    private var recurrenceSummaryText: String {
        let summary = window.recurrence.summaryText
        if summary.isEmpty && window.recurrence.kindChoice != .everyDay {
            return "Select days"
        }
        return summary
    }

    var body: some View {
        HStack(spacing: 12) {

            VStack(alignment: .leading, spacing: 6) {

                HStack(spacing: 8) {
                    DatePicker(
                        "",
                        selection: $window.start,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()

                    Text("–")
                        .foregroundStyle(.secondary)

                    DatePicker(
                        "",
                        selection: $window.end,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                }
                .font(.footnote)

                if crossesMidnight {
                    Text("Crosses midnight")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button {
                    showingRecurrenceEditor = true
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Repeat")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(recurrenceSummaryText)
                            .foregroundStyle(showsRepeatWarning ? .red : .primary)
                        if showsRepeatWarning {
                            Text("(select ≥ 1 day)")
                                .foregroundStyle(.red)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .font(.footnote)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .sheet(isPresented: $showingRecurrenceEditor) {
            RecurrenceEditorSheet(recurrence: $window.recurrence)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Recurrence UI helpers

private enum RecurrenceKindChoice: Hashable, CaseIterable {
    case everyDay
    case weekly
    case monthly

    var title: String {
        switch self {
        case .everyDay: return "Every day"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

extension SlotRecurrence {
    fileprivate var kindChoice: RecurrenceKindChoice {
        switch self {
        case .everyDay: return .everyDay
        case .specificWeekdays: return .weekly
        case .specificMonthDays: return .monthly
        }
    }
}

private struct RecurrenceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var recurrence: SlotRecurrence

    @State private var kind: RecurrenceKindChoice = .everyDay
    // One entry per kind; preserves picks when switching between kinds.
    @State private var recurrenceByKind: [RecurrenceKindChoice: SlotRecurrence] = [
        .everyDay: .everyDay,
        .weekly: .specificWeekdays([2, 3, 4, 5, 6]),  // Mon–Fri default
        .monthly: .specificMonthDays([1]),
    ]

    private var currentRecurrence: SlotRecurrence { recurrenceByKind[kind]! }

    /// Fixed detent heights per kind – avoids the layout cycle that dynamic
    /// GeometryReader-based sizing caused (sheet measuring → detent change →
    /// re-measure → oscillation → auto-dismiss).
    private var detentForKind: CGFloat {
        switch kind {
        case .everyDay: return 260
        case .weekly: return 380
        case .monthly: return 500
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Repeat", selection: $kind) {
                        ForEach(RecurrenceKindChoice.allCases, id: \.self) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)

                    if kind == .weekly || kind == .monthly {
                        VStack(alignment: .leading, spacing: 12) {
                            if kind == .weekly {
                                WeeklySpecificDaysPicker(
                                    selectedWeekdays: Binding(
                                        get: { currentRecurrence.weekdaysSet },
                                        set: { recurrenceByKind[.weekly] = .specificWeekdays($0) }
                                    )
                                )
                            } else {
                                MonthlySpecificDaysPicker(
                                    selectedMonthDays: Binding(
                                        get: { currentRecurrence.monthDaysSet },
                                        set: { recurrenceByKind[.monthly] = .specificMonthDays($0) }
                                    )
                                )
                            }

                            if !currentRecurrence.isValidSelection {
                                Text("Please select at least 1 day.")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Repeat")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        recurrence = currentRecurrence
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!currentRecurrence.isValidSelection)
                }
            }
            .onAppear {
                kind = recurrence.kindChoice
                recurrenceByKind[kind] = recurrence
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.height(detentForKind)])
    }
}

extension SlotRecurrence {
    fileprivate var weekdaysSet: Set<Int> {
        switch self {
        case .specificWeekdays(let set): return set
        default: return []
        }
    }
    fileprivate var monthDaysSet: Set<Int> {
        switch self {
        case .specificMonthDays(let set): return set
        default: return []
        }
    }
}

private struct WeeklySpecificDaysPicker: View {
    @Binding var selectedWeekdays: Set<Int>  // 1=Sun ... 7=Sat

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Days of week")
                .font(.footnote.weight(.semibold))

            let calendar = Calendar.current
            let symbols = calendar.veryShortWeekdaySymbols

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(1...7, id: \.self) { weekday in
                    let isSelected = selectedWeekdays.contains(weekday)
                    Button {
                        toggle(weekday)
                    } label: {
                        Text(symbols[weekday - 1])
                            .font(.callout.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .background(
                                isSelected ? Color.accentColor : Color(.secondarySystemBackground)
                            )
                            .foregroundStyle(isSelected ? .white : .primary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(calendar.weekdaySymbols[weekday - 1])
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func toggle(_ weekday: Int) {
        if selectedWeekdays.contains(weekday) {
            selectedWeekdays.remove(weekday)
        } else {
            selectedWeekdays.insert(weekday)
        }
    }
}

private struct MonthlySpecificDaysPicker: View {
    @Binding var selectedMonthDays: Set<Int>  // 1...31

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Days of month")
                    .font(.footnote.weight(.semibold))
                Spacer(minLength: 8)
                Text(selectedSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(1...31, id: \.self) { day in
                    let isSelected = selectedMonthDays.contains(day)
                    Button {
                        toggle(day)
                    } label: {
                        Text("\(day)")
                            .font(.callout.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .background(
                                isSelected ? Color.accentColor : Color(.secondarySystemBackground)
                            )
                            .foregroundStyle(isSelected ? .white : .primary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var selectedSummary: String {
        let ordered = selectedMonthDays.sorted()
        if ordered.isEmpty { return "Select days" }
        let joined = ordered.map(String.init).joined(separator: ", ")
        return "\(joined) every month"
    }

    private func toggle(_ day: Int) {
        if selectedMonthDays.contains(day) {
            selectedMonthDays.remove(day)
        } else {
            selectedMonthDays.insert(day)
        }
    }
}
