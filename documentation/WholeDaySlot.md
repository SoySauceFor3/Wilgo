# Whole Day Slot — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**PRD:** [full-day slot option](https://www.notion.so/full-day-slot-option-33b4b58e32c38068bd43d0b0cbb2f491?source=copy_link)  
**Tracking:** [full-day slot option](https://www.notion.so/full-day-slot-option-33b4b58e32c38068bd43d0b0cbb2f491?source=copy_link)  
**Tag:** `#WholeDaySlot`

---

## Context

Users currently must specify a start and end time for each reminder slot. We want to support a "whole day" slot — one where the live activity is shown all day. The sentinel representation is `start == end` on the `Slot` model. This is already mathematically correct: the existing `contains(timeOfDay:)` midnight-crossing branch (`timeMinutes >= startMinutes || timeMinutes <= endMinutes`) evaluates to `true` for all times when `startMinutes == endMinutes`.

No model migration is needed. Changes are purely in display logic and UI.

---

## Architecture Summary

We add `isWholeDay: Bool` computed property (`start == end`) to `Slot` and to the form-layer `SlotWindow`. All display callsites that show time text gate on this flag first. In `SlotWindowRow` we add a "Whole day" toggle; when on, only the start time picker remains visible and `end` is kept in sync with `start`. `timeOfDayText` shows `"Whole day (from HH:mm)"` when `isWholeDay`. The existing `contains`, `isActive`, `remainingFraction`, and snooze logic all work without changes.

---

## Design Decisions

### Sentinel vs. model flag

**Decision:** Use `start == end` as the sentinel for "whole day". No new stored property on `Slot`.

**Why not add `isWholeDay: Bool` to the SwiftData model?** That would require a schema migration with no functional benefit. The sentinel is unambiguous — there is no valid "empty" slot meaning in the current codebase, and `start == end` is unreachable in normal time-range use.

**Risk: future confusion** if someone reads `start == end` without knowing the convention. Mitigated by a doc comment on `isWholeDay` in `Slot`.

### "Whole day" toggle in the row UI

**Decision:** Add a `Toggle("Whole day", ...)` inside `SlotWindowRow`. When turned on, the end picker is hidden and `end` is kept in sync with `start` via the binding. The start picker remains visible so the user can set their day-anchor time. Default start on first toggle-on: midnight `00:00`. When turned off, restore a default 1-hour window with `end = start + 1 hour`.

**Why not a dedicated preset button?** A toggle is the clearest affordance for a binary on/off state and matches the existing "Reminders" toggle pattern in the form.

**Potential future enhancement:** Add a global "Default whole-day start time" setting in the app's Settings screen, so users don't have to set it per slot. Not implemented now — the per-slot picker covers the need with minimal friction.

---

## Major Model Changes


| Entity                                                      | Change                                                                                                                            |
| ----------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `Shared/Models/Slot.swift`                                  | Add `var isWholeDay: Bool` computed property; update `timeOfDayText` and `label`                                                  |
| `Wilgo/Features/Commitments/SlotView.swift`                 | Add `isWholeDay` to `SlotWindow`; update `SlotWindowRow` with toggle + conditional pickers; update "Crosses midnight" label logic |
| `Wilgo/Features/Notifications/NowLiveActivityManager.swift` | Use `slot.isWholeDay` guard before rendering `timeOfDayText`                                                                      |
| `WidgetExtension/CurrentCommitmentWidget.swift`             | Same as above                                                                                                                     |
| `Wilgo/Features/Stage/Upcoming.swift`                       | Same as above                                                                                                                     |
| `Wilgo/Features/Stage/Current.swift`                        | Same as above                                                                                                                     |


---

## Commit Plan

---

### Phase 1 — Model & logic layer

#### Commit 1 — feat: add isWholeDay sentinel to Slot and SlotWindow `#WholeDaySlot`

**Goal:** Establish the sentinel convention and update all display text.

**Modify:** `Shared/Models/Slot.swift`

Add after `var endToday`:

```swift
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
```

Replace `timeOfDayText`:

```swift
var timeOfDayText: String {
    if isWholeDay {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "Whole day (from \(formatter.string(from: start)))"
    }
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
}
```

`label` already calls `timeOfDayText`, so it picks up "Whole day" automatically — no change needed there.

**Modify:** `Wilgo/Features/Commitments/SlotView.swift` — add `isWholeDay` to `SlotWindow`:

```swift
struct SlotWindow: Identifiable {
    let id = UUID()
    var start: Date
    var end: Date
    var recurrence: SlotRecurrence = .everyDay

    var isWholeDay: Bool {
        let calendar = Calendar.current
        let s = calendar.dateComponents([.hour, .minute], from: start)
        let e = calendar.dateComponents([.hour, .minute], from: end)
        return s.hour == e.hour && s.minute == e.minute
    }
}
```

**Tests to write:** `WilgoTests/Slot/SlotWholeDayTests.swift`

```swift
import Testing
import Foundation
@testable import Wilgo

struct SlotWholeDayTests {

    // MARK: - isWholeDay

    @Test func isWholeDay_whenStartEqualsEnd_returnsTrue() {
        let ref = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: .now)!
        let slot = Slot(start: ref, end: ref)
        #expect(slot.isWholeDay == true)
    }

    @Test func isWholeDay_whenStartDiffersFromEnd_returnsFalse() {
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
        let end   = cal.date(bySettingHour: 10, minute: 0, second: 0, of: .now)!
        let slot = Slot(start: start, end: end)
        #expect(slot.isWholeDay == false)
    }

    // MARK: - contains (whole day)

    @Test func contains_wholeDaySlot_returnsTrueForAnyTime() throws {
        let cal = Calendar.currents
        let ref = cal.date(bySettingHour: 0, minute: 0, second: 0, of: .now)!
        let slot = Slot(start: ref, end: ref)

        let times: [Int] = [0, 3, 9, 12, 17, 23]
        for hour in times {
            let t = cal.date(bySettingHour: hour, minute: 30, second: 0, of: .now)!
            #expect(slot.contains(timeOfDay: t), "Expected whole-day slot to contain hour \(hour)")
        }
    }

    // MARK: - timeOfDayText

    @Test func timeOfDayText_wholeDaySlot_containsWholeDayPrefix() {
        let ref = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
        let slot = Slot(start: ref, end: ref)
        #expect(slot.timeOfDayText.hasPrefix("Whole day (from "))
    }

    @Test func timeOfDayText_normalSlot_returnsTimeRange() {
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
        let end   = cal.date(bySettingHour: 10, minute: 0, second: 0, of: .now)!
        let slot = Slot(start: start, end: end)
        #expect(slot.timeOfDayText != "Whole day")
        #expect(slot.timeOfDayText.contains("–"))
    }
}
```

Run tests:

```
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' \
  -only-testing WilgoTests/SlotWholeDayTests
```

Expected: all 4 pass.

---

### Phase 2 — UI: form row

#### Commit 2 — feat: add Whole Day toggle to SlotWindowRow `#WholeDaySlot`

**Goal:** Let users toggle whole-day mode in the commitment form. When on, hides the end picker and keeps `end` in sync with `start` (user can still pick their day-anchor start time). When off, restores a 1-hour window (`end = start + 1 hour`).

**Modify:** `Wilgo/Features/Commitments/SlotView.swift` — `SlotWindowRow`

Replace the existing `crossesMidnight` computed property and the `body` of `SlotWindowRow` with the following. Keep everything else (`showingRecurrenceEditor`, `showsRepeatWarning`, `recurrenceSummaryText`) unchanged.

```swift
struct SlotWindowRow: View {
    let index: Int
    @Binding var window: SlotWindow
    var onDelete: () -> Void

    private var crossesMidnight: Bool {
        !window.isWholeDay && window.end < window.start
    }
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

                Toggle("Whole day", isOn: wholeDayBinding)
                    .font(.footnote)

                if window.isWholeDay {
                    // Only show the start (day-anchor) picker; end is kept in sync.
                    HStack(spacing: 8) {
                        Text("From")
                            .foregroundStyle(.secondary)
                        DatePicker(
                            "",
                            selection: $window.start,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .onChange(of: window.start) { _, newStart in
                            window.end = newStart
                        }
                    }
                    .font(.footnote)
                } else {
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

    private var wholeDayBinding: Binding<Bool> {
        Binding(
            get: { window.isWholeDay },
            set: { newValue in
                if newValue {
                    // Keep start as-is (user's day-anchor); sync end to start.
                    window.end = window.start
                } else {
                    // Restore a 1-hour window: keep start, set end = start + 1 hour.
                    let end = Calendar.current.date(byAdding: .hour, value: 1, to: window.start) ?? window.start
                    window.end = end
                }
            }
        )
    }
}
```

**Manual verification:** Open the commitment form (add or edit a commitment), add a reminder window. Verify:

- "Whole day" toggle appears.
- Toggling on hides the end picker; shows "From [time]" with only the start picker.
- Changing the start time while whole-day is on keeps end in sync (both always equal).
- Slot label in the list shows `"Whole day (from 9:00 AM)"` (or whatever start is).
- Toggling off restores both pickers with end = start + 1 hour.
- "Crosses midnight" is never shown while whole-day is on.
- "Repeat" row is always visible regardless of toggle state.

---

### Phase 3 — Display callsites

#### Commit 3 — feat: show "Whole day" in stage and widget callsites `#WholeDaySlot`

**Goal:** All places that call `slot.timeOfDayText` or `slot.label` already get "Whole day" for free after Commit 1. This commit is a defensive pass to confirm no callsite breaks, and fixes any that need special handling.

**Review each callsite:**

`Wilgo/Features/Stage/Upcoming.swift:18` — uses `slots[0].timeOfDayText`. No change needed; "Whole day" renders fine as a `Text`.

`Wilgo/Features/Stage/Current.swift:21` — uses `slots.first?.timeOfDayText ?? "No slot"`. No change needed.

`Wilgo/Features/Notifications/NowLiveActivityManager.swift:70` — uses `slots[0].timeOfDayText`. No change needed.

`WidgetExtension/CurrentCommitmentWidget.swift:82` — uses `wb.slots.first?.timeOfDayText`. No change needed.

**Build to confirm no compiler errors:**

```
xcodebuild build -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588'
```

**Run full test suite:**

```
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588'
```

Expected: all tests pass except the pre-existing failing test `CommitmentStageSnoozeTests/stageStatus_snoozeDoesNotAffectFutureOccurrence` — ignore that one.

Commit:

```bash
git commit -m "feat: whole-day slot display verified across all callsites #WholeDaySlot

tracking: https://www.notion.so/full-day-slot-option-33b4b58e32c38068bd43d0b0cbb2f491" --allow-empty
```

> Note: if no file changes were needed, use `--allow-empty` for the verification commit, or skip and fold into Commit 2.

---

## Critical Files


| File                                            | Role                                         |
| ----------------------------------------------- | -------------------------------------------- |
| `Shared/Models/Slot.swift`                      | Sentinel logic + display text                |
| `Wilgo/Features/Commitments/SlotView.swift`     | Form row toggle UI + `SlotWindow.isWholeDay` |
| `WilgoTests/Slot/SlotWholeDayTests.swift` (new) | Unit tests for sentinel behavior             |


### Dependency Graph

```
Commit 1: isWholeDay sentinel + model display text + tests
    |
    +-- Commit 2: SlotWindowRow toggle UI   [after 1]
    |
    +-- Commit 3: callsite verification      [after 1, parallel with 2]
```

Commits 2 and 3 are independent of each other and can run in parallel after Commit 1.