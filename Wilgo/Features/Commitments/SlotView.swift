import SwiftUI

// MARK: - Reminder windows section (used by commitment form)

struct ReminderWindowsSection: View {
    @Binding var slotWindows: [SlotWindow]

    var body: some View {
        ForEach(Array(slotWindows.enumerated()), id: \.element.id) { index, _ in
            SlotWindowRow(
                index: index,
                window: $slotWindows[index]
            ) {
                slotWindows.remove(at: index)
            }
        }

        Button {
            let (defaultStart, defaultEnd) = defaultWindowForNewSlot()
            slotWindows.append(SlotWindow(start: defaultStart, end: defaultEnd))
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

// MARK: - SlotWindow (shared value type)

struct SlotWindow: Identifiable {
    let id = UUID()
    var start: Date
    var end: Date
    var recurrence: SlotRecurrence = .everyDay

    /// Returns true when start and end represent the same time-of-day,
    /// which is the sentinel for "active the whole day".
    /// The existing `contains(timeOfDay:)` midnight-crossing branch already
    /// returns `true` for all times in this case.
    var isWholeDay: Bool {
        let calendar = Calendar.current
        let s = calendar.dateComponents([.hour, .minute], from: start)
        let e = calendar.dateComponents([.hour, .minute], from: end)
        return s.hour == e.hour && s.minute == e.minute
    }
}

// MARK: - SlotWindowRow (per-slot UI, including recurrence)

struct SlotWindowRow: View {
    let index: Int
    @Binding var window: SlotWindow
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
                Text("Slot \(index + 1)")
                    .font(.subheadline.weight(.semibold))

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
                .sheet(isPresented: $showingRecurrenceEditor) {
                    RecurrenceEditorSheet(recurrence: $window.recurrence)
                }
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
    @State private var measuredContentHeight: CGFloat = 0
    @State private var cachedWeekdays: Set<Int> = []
    @State private var cachedMonthDays: Set<Int> = []

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
                                        get: { cachedWeekdays },
                                        set: { newValue in
                                            cachedWeekdays = newValue
                                            recurrence = .specificWeekdays(newValue)
                                        }
                                    )
                                )
                            } else {
                                MonthlySpecificDaysPicker(
                                    selectedMonthDays: Binding(
                                        get: { cachedMonthDays },
                                        set: { newValue in
                                            cachedMonthDays = newValue
                                            recurrence = .specificMonthDays(newValue)
                                        }
                                    )
                                )
                            }

                            if !recurrence.isValidSelection {
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
                .readHeight(into: $measuredContentHeight)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Repeat")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .disabled(!recurrence.isValidSelection)
                }
            }
            .onAppear {
                kind = recurrence.kindChoice
                cachedWeekdays = recurrence.weekdaysSet
                cachedMonthDays = recurrence.monthDaysSet
                normalizeForKind()
            }
            .onChange(of: kind) { oldKind, _ in
                // Preserve the user's last picks per-kind while switching.
                switch oldKind {
                case .weekly:
                    cachedWeekdays = recurrence.weekdaysSet
                case .monthly:
                    cachedMonthDays = recurrence.monthDaysSet
                case .everyDay:
                    break
                }
                normalizeForKind()
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.height(preferredDetentHeight)])
    }

    private func normalizeForKind() {
        switch kind {
        case .everyDay:
            recurrence = .everyDay
        case .weekly:
            let chosen = cachedWeekdays.isEmpty ? [2, 3, 4, 5, 6] : cachedWeekdays  // Mon–Fri default
            cachedWeekdays = chosen
            recurrence = .specificWeekdays(chosen)
        case .monthly:
            let chosen = cachedMonthDays.isEmpty ? [1] : cachedMonthDays
            cachedMonthDays = chosen
            recurrence = .specificMonthDays(chosen)
        }
    }

    private var preferredDetentHeight: CGFloat {
        // Include navigation bar + safe-area-ish allowance.
        let chrome: CGFloat = 140
        let minHeight: CGFloat = 260
        let maxHeight: CGFloat = 720
        let candidate = measuredContentHeight + chrome
        return min(max(candidate, minHeight), maxHeight)
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

private enum SheetHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    fileprivate func readHeight(into binding: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: SheetHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(SheetHeightPreferenceKey.self) { binding.wrappedValue = $0 }
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
