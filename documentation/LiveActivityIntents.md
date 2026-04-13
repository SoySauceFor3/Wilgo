# Plan: Replace Live Activity Deeplinks with AppIntents

## Context

The Live Activity's "Done" and "Snooze" buttons currently use `Link(destination:)` with `wilgo://` deeplinks. Tapping either button foregrounds the app, which is disruptive — especially from the Lock Screen. Now that `CheckInIntent` (AppIntent) already exists and runs directly in the extension without launching the app, we should use the same pattern for both buttons.

## Approach

1. **Create `SnoozeIntent`** — mirrors `CheckInIntent` exactly, but fetches a `Slot` and calls `SlotSnooze.create(slot:at:in:)`
2. **Replace `DoneCapsuleLink` and `SnoozeCapsuleLink`** — swap `Link` views for `Button(intent:)` views using the existing capsule styling
3. **Remove the URL helper functions** — `doneURL` and `snoozeURL` become dead code
4. **Clean up `WilgoApp` deeplink handler** — remove the `"done"` and `"snooze"` cases (undo for Done from Live Activity is acceptable to drop; it was never wired to `checkInUndoManager` anyway)

No changes to `NowAttributes.ContentState` needed — `commitmentId` and `slotId` are already present.

## Critical Files

| File | Change |
|---|---|
| `WidgetExtension/SnoozeIntent.swift` | **Create** — new AppIntent |
| `WidgetExtension/NowLiveActivity.swift` | Replace `Link` buttons with `Button(intent:)` |
| `Wilgo/WilgoApp.swift` | Remove `"done"` and `"snooze"` cases from `handleDeepLink` |

## Reference: Existing Patterns to Reuse

- `WidgetExtension/CheckInIntent.swift` — exact schema/container setup to copy for `SnoozeIntent`
- `WidgetExtension/CurrentCommitmentWidget.swift:276` — `Button(intent:) { ... }.buttonStyle(.plain)` pattern
- `Shared/Models/SlotSnooze.swift` — `SlotSnooze.create(slot:at:in:)` factory method to call in SnoozeIntent
- `Shared/WilgoConstants.swift` — `appGroupID`, `currentCommitmentWidgetKind`

## Step-by-Step

### Commit 1: Add SnoozeIntent

**File:** `WidgetExtension/SnoozeIntent.swift` (new)

```swift
import AppIntents
import SwiftData
import WidgetKit

struct SnoozeIntent: AppIntent {
    static var title: LocalizedStringResource = "Snooze"

    @Parameter(title: "Slot ID")
    var slotId: String

    init() { self.slotId = "" }

    init(slotId: UUID) {
        self.slotId = slotId.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: slotId) else { return .result() }
        guard let groupContainer = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WilgoConstants.appGroupID)
        else { return .result() }

        let storeURL = groupContainer
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("default.store")

        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, PositivityToken.self, SlotSnooze.self])
        let config = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<Slot>(predicate: #Predicate { $0.id == id })
        guard let slot = (try? context.fetch(descriptor))?.first else { return .result() }

        SlotSnooze.create(slot: slot, in: context)
        try context.save()

        WidgetCenter.shared.reloadTimelines(ofKind: WilgoConstants.currentCommitmentWidgetKind)
        return .result()
    }
}
```

### Commit 2: Update NowLiveActivity — replace Link buttons with Button(intent:)

**File:** `WidgetExtension/NowLiveActivity.swift`

- Replace `DoneCapsuleLink` struct: change `Link(destination:)` to `Button(intent: CheckInIntent(commitmentId: commitmentId)) { ... }`
  - Add `let commitmentId: UUID` property instead of `let destination: URL`
- Replace `SnoozeCapsuleLink` struct: change `Link(destination:)` to `Button(intent: SnoozeIntent(slotId: slotId)) { ... }`
  - Add `let slotId: UUID` property instead of `let destination: URL`
- Update all call sites in the lock screen and Dynamic Island regions to pass the UUID from `context.state`
- Delete `doneURL(commitmentId:)` and `snoozeURL(slotId:)` helper functions

### Commit 3: Remove dead deeplink cases from WilgoApp

**File:** `Wilgo/WilgoApp.swift`

- Remove `case "snooze":` block from `handleDeepLink`
- Remove `case "done":` block from `handleDeepLink` (the Live Activity path; the check-in undo toast was never wired from the Live Activity anyway)
- Keep `case "commitment":` (used by other notification/widget deeplinks)

## Verification

1. **Build** — no compiler errors, both intents resolve in WidgetExtension target
2. **Simulator:** Start a Live Activity → tap "Done" from notification banner → app does NOT foreground, check-in is recorded in SwiftData
3. **Simulator:** Tap "Snooze" → app does NOT foreground, SlotSnooze record created
4. **Lock Screen (physical device):** Tap both buttons from Lock Screen — confirm no app launch
5. **Existing widget:** `CurrentCommitmentWidget` check-in button still works (unaffected)
6. Run unit tests for `SlotSnooze.create` if they exist
