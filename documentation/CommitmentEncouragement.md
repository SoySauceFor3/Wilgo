# Commitment Encouragement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users write per-commitment encouragement phrases that are shown randomly in `CommitmentStatsCard` and `NowLiveActivity`.

**Architecture:** Add `encouragements: [String]` to the `Commitment` SwiftData model, wire it through `CommitmentFormFields` with a `ReminderWindowsSection`-style CRUD UI, display a random pick in `CommitmentStatsCard`'s title tile (accent yellow italic, no "Commitment" label), and pass it through `NowAttributes.ContentState` to show below the slot time in the lock screen Live Activity.

**Tech Stack:** SwiftUI, SwiftData, ActivityKit

**PRD:** https://www.notion.so/3274b58e32c380288d98f8da284a08c8

---

## File Map

| File                                                                    | Change                                                                |
| ----------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `Shared/Models/Commitment.swift`                                        | Add `encouragements: [String]` property                               |
| `Shared/NowAttributes.swift`                                            | Add `encouragementText: String?` to `ContentState`                    |
| `Wilgo/Features/Commitments/CommitmentFormFields.swift`                 | Add `encouragements` binding + `EncouragementSection` view            |
| `Wilgo/Features/Commitments/AddCommitView.swift`                        | Add `@State var encouragements: [String]` + pass to form + persist    |
| `Wilgo/Features/Commitments/EditCommitmentView.swift`                   | Add `@State var encouragements: [String]` + pass to form + persist    |
| `Wilgo/Features/Commitments/SingleCommitment/CommitmentStatsCard.swift` | Remove "Commitment" label, show random encouragement in yellow italic |
| `Wilgo/Features/Notifications/NowLiveActivityManager.swift`             | Pick random encouragement + pass to `ContentState`                    |
| `WidgetExtension/NowLiveActivity.swift`                                 | Render `encouragementText` in lock screen banner + update preview     |

---

## Task 1: Add `encouragements` to the `Commitment` model

**Files:**

- Modify: `Shared/Models/Commitment.swift`

- [ ] **Step 1: Add the property to `Commitment`**

In `Shared/Models/Commitment.swift`, add `encouragements` after `gracePeriods`:

```swift
var gracePeriods: [GracePeriod] = []

var encouragements: [String] = []
```

- [ ] **Step 2: Build and confirm no errors**

Build in Xcode (⌘B). SwiftData auto-migrates `[String]` fields with a default value — no migration plan needed.

Expected: build succeeds with no errors or warnings related to this change.

- [ ] **Step 3: Commit**

```bash
git add Wilgo/Shared/Models/Commitment.swift
git commit -m "feat: add encouragements property to Commitment model"
```

---

## Task 2: Add `EncouragementSection` to `CommitmentFormFields`

**Files:**

- Modify: `Wilgo/Features/Commitments/CommitmentFormFields.swift`

- [ ] **Step 1: Add `encouragements` binding to `CommitmentFormFields`**

Replace the struct signature and body:

```swift
struct CommitmentFormFields: View {
    @Binding var title: String
    @Binding var slotWindows: [SlotDraft]
    @Binding var target: Target
    @Binding var proofOfWorkType: ProofOfWorkType
    @Binding var punishment: String
    @Binding var encouragements: [String]

    var body: some View {
        Section("Basics") {
            TextField("Title", text: $title)
        }
        ReminderWindowsSection(slotWindows: $slotWindows)
        EncouragementSection(encouragements: $encouragements)

        Section("Target") {
        // ... rest unchanged
```

- [ ] **Step 2: Add `EncouragementSection` view at the bottom of the file**

Append after the closing brace of `CommitmentFormFields`:

```swift
// MARK: - Encouragement section (used by commitment form)

struct EncouragementSection: View {
    @Binding var encouragements: [String]
    @FocusState private var focusedIndex: Int?

    var body: some View {
        Section {
            ForEach(Array(encouragements.enumerated()), id: \.offset) { index, _ in
                HStack {
                    TextField("e.g. Just do a little bit", text: $encouragements[index])
                        .focused($focusedIndex, equals: index)
                    Spacer()
                    Button(role: .destructive) {
                        encouragements.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Button {
                encouragements.append("")
                focusedIndex = encouragements.count - 1
            } label: {
                Label("Add encouragement", systemImage: "plus")
            }
        } header: {
            Text("Encouragement")
        } footer: {
            Text("Shown randomly while you work.")
        }
    }
}
```

- [ ] **Step 3: Build and confirm no errors**

Build in Xcode (⌘B). Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Wilgo/Wilgo/Features/Commitments/CommitmentFormFields.swift
git commit -m "feat: add EncouragementSection to CommitmentFormFields"
```

---

## Task 3: Wire `encouragements` through `AddCommitmentView`

**Files:**

- Modify: `Wilgo/Features/Commitments/AddCommitView.swift`

- [ ] **Step 1: Add state and wire to form**

Add `@State private var encouragements: [String] = []` after the existing `@State` declarations, then pass it to `CommitmentFormFields`:

```swift
@State private var encouragements: [String] = []
```

Update the `CommitmentFormFields` call in `body`:

```swift
CommitmentFormFields(
    title: $title,
    slotWindows: $slotWindows,
    target: $target,
    proofOfWorkType: $proofOfWorkType,
    punishment: $punishment,
    encouragements: $encouragements
)
```

- [ ] **Step 2: Persist encouragements on save**

In `persistCommitment(grace:)`, after `modelContext.insert(commitment)`, add:

```swift
commitment.encouragements = encouragements.map {
    $0.trimmingCharacters(in: .whitespacesAndNewlines)
}.filter { !$0.isEmpty }
```

- [ ] **Step 3: Build and confirm no errors**

Build in Xcode (⌘B). Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Wilgo/Wilgo/Features/Commitments/AddCommitView.swift
git commit -m "feat: wire encouragements through AddCommitmentView"
```

---

## Task 4: Wire `encouragements` through `EditCommitmentView`

**Files:**

- Modify: `Wilgo/Features/Commitments/EditCommitmentView.swift`

- [ ] **Step 1: Add state initialized from the commitment**

Add after the existing `@State private var punishment: String`:

```swift
@State private var encouragements: [String]
```

In `init(commitment:)`, after `_punishment = State(...)`:

```swift
_encouragements = State(initialValue: commitment.encouragements)
```

- [ ] **Step 2: Pass to form**

Update the `CommitmentFormFields` call:

```swift
CommitmentFormFields(
    title: $title,
    slotWindows: $slotWindows,
    target: $target,
    proofOfWorkType: $proofOfWorkType,
    punishment: $punishment,
    encouragements: $encouragements
)
```

- [ ] **Step 3: Persist on save**

In `saveChanges(grace:)`, after `commitment.punishment = ...`:

```swift
commitment.encouragements = encouragements.map {
    $0.trimmingCharacters(in: .whitespacesAndNewlines)
}.filter { !$0.isEmpty }
```

- [ ] **Step 4: Build and confirm no errors**

Build in Xcode (⌘B). Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Wilgo/Wilgo/Features/Commitments/EditCommitmentView.swift
git commit -m "feat: wire encouragements through EditCommitmentView"
```

---

## Task 5: Show encouragement in `CommitmentStatsCard`

**Files:**

- Modify: `Wilgo/Features/Commitments/SingleCommitment/CommitmentStatsCard.swift`

- [ ] **Step 1: Add a computed property for the random encouragement**

Add inside `CommitmentStatsCard`, after `targetCycleLabel`:

```swift
private var randomEncouragement: String? {
    commitment.encouragements.isEmpty ? nil : commitment.encouragements.randomElement()
}
```

- [ ] **Step 2: Update the Commitment tile — remove the label, add encouragement**

Find the `statTile` call with `title: "Commitment"` in `body`. Replace it:

```swift
statTile(
    title: "",
    background: tileBackground,
    cornerRadius: cornerRadius
) {
    VStack(alignment: .leading, spacing: 2) {
        Text(commitment.title)
            .font(.headline)
            .foregroundStyle(.primary)
        if let encouragement = randomEncouragement {
            Text(encouragement)
                .font(.caption)
                .foregroundStyle(.yellow)
                .italic()
        }
    }
}
.frame(height: cellWidth)
.gridCellColumns(3)
```

Note: the `title: ""` removes the "Commitment" label. The `statTile` helper renders nothing for an empty title string since it's just a `Text(title)` with `.caption2`.

- [ ] **Step 3: Build and visually verify in Preview**

Build in Xcode (⌘B) and run the `CommitmentStatsCard` preview if one exists, or launch the app on simulator and navigate to the Stage view. Confirm:

- "Commitment" label is gone
- Commitment title still shows
- Yellow italic encouragement appears below title (if the commitment has one)
- When no encouragements exist, the tile looks like before (title only)

- [ ] **Step 4: Commit**

```bash
git add Wilgo/Wilgo/Features/Commitments/SingleCommitment/CommitmentStatsCard.swift
git commit -m "feat: show random encouragement in CommitmentStatsCard title tile"
```

---

## Task 6: Thread `encouragementText` through `NowAttributes`

**Files:**

- Modify: `Shared/NowAttributes.swift`

- [ ] **Step 1: Add `encouragementText` to `ContentState`**

```swift
public struct ContentState: Codable, Hashable {
    var commitmentTitle: String
    var slotTimeText: String
    var commitmentId: UUID
    var slotId: UUID
    var secondaryTitles: [String]
    /// Random encouragement sentence for the primary commitment. Nil if none set.
    var encouragementText: String?

    public var hasCurrentCommitment: Bool {
        !commitmentTitle.isEmpty && !slotTimeText.isEmpty
    }
}
```

- [ ] **Step 2: Build and confirm no errors**

Build in Xcode (⌘B). Expected: build succeeds. (The widget extension shares this type — it will also pick up the new field automatically.)

- [ ] **Step 3: Commit**

```bash
git add Wilgo/Shared/NowAttributes.swift
git commit -m "feat: add encouragementText to NowAttributes.ContentState"
```

---

## Task 7: Pass encouragement from `NowLiveActivityManager`

**Files:**

- Modify: `Wilgo/Features/Notifications/NowLiveActivityManager.swift`

- [ ] **Step 1: Update `makeLiveActivityContentState` to pick a random encouragement**

Replace the existing `makeLiveActivityContentState` method:

```swift
private static func makeLiveActivityContentState(
    from currentSlots: [CommitmentAndSlot.WithBehind]
) -> NowAttributes.ContentState? {
    guard let (commitment, slots, _) = currentSlots.first else { return nil }
    let commitmentId = commitment.id
    let slotId = slots[0].id
    let secondaryTitles = currentSlots.dropFirst().map(\.commitment.title)
    let encouragementText = commitment.encouragements.randomElement()
    return NowAttributes.ContentState(
        commitmentTitle: commitment.title,
        slotTimeText: slots[0].timeOfDayText,
        commitmentId: commitmentId,
        slotId: slotId,
        secondaryTitles: secondaryTitles,
        encouragementText: encouragementText
    )
}
```

- [ ] **Step 2: Build and confirm no errors**

Build in Xcode (⌘B). Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Wilgo/Wilgo/Features/Notifications/NowLiveActivityManager.swift
git commit -m "feat: pass random encouragement to NowLiveActivity content state"
```

---

## Task 8: Render encouragement in `NowLiveActivity`

**Files:**

- Modify: `WidgetExtension/NowLiveActivity.swift`

- [ ] **Step 1: Add encouragement line in the lock screen banner**

In the lock screen `ActivityConfiguration` content closure, find the `VStack` inside `HStack(alignment: .top, spacing: 12)`. Currently it has:

```swift
VStack(alignment: .leading, spacing: 3) {
    Text(context.state.commitmentTitle)
        .font(.headline)
        .foregroundStyle(.primary)
        .lineLimit(1)
    Text(context.state.slotTimeText)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
}
```

Replace with:

```swift
VStack(alignment: .leading, spacing: 3) {
    Text(context.state.commitmentTitle)
        .font(.headline)
        .foregroundStyle(.primary)
        .lineLimit(1)
    Text(context.state.slotTimeText)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    if let encouragement = context.state.encouragementText {
        Text(encouragement)
            .font(.caption)
            .foregroundStyle(.yellow)
            .italic()
            .lineLimit(1)
    }
}
```

- [ ] **Step 2: Update the preview `ContentState` to include `encouragementText`**

Find the `withCommitment` static var at the bottom of the file and add the new field:

```swift
fileprivate static var withCommitment: NowAttributes.ContentState {
    NowAttributes.ContentState(
        commitmentTitle: "Morning reading",
        slotTimeText: "9:00 AM – 11:00 AM",
        commitmentId: UUID(),
        slotId: UUID(),
        secondaryTitles: ["Walk dog", "Email inbox"],
        encouragementText: "Just do a little bit"
    )
}
```

- [ ] **Step 3: Build and visually verify**

Build in Xcode (⌘B). Open the `NowLiveActivity` preview in Xcode canvas and confirm:

- Yellow italic encouragement appears below the slot time
- It sits above the secondary commitments line
- When `encouragementText` is nil the layout is unchanged

- [ ] **Step 4: Commit**

```bash
git add Wilgo/WidgetExtension/NowLiveActivity.swift
git commit -m "feat: render encouragementText in NowLiveActivity lock screen banner"
```

---

## Verification Checklist

- [ ] **Create commitment with encouragements:** Open app → "+" → fill in title → Encouragement section shows → add 2 sentences → save. Confirm they persist (edit the commitment and see them pre-filled).
- [ ] **Edit commitment:** Open existing commitment → Edit → modify/delete encouragement → save. Confirm changes persist.
- [ ] **CommitmentStatsCard:** On Stage view, a commitment with encouragements shows yellow italic text below the title. One with no encouragements shows title only, no label.
- [ ] **Empty encouragements trimmed:** Save a commitment with a blank encouragement field — it should not appear in the list (filtered out on save).
- [ ] **Live Activity:** Trigger a Live Activity (enter a slot window with an active commitment that has encouragements). Confirm yellow italic text appears below the slot time on the lock screen.
- [ ] **Live Activity — no encouragements:** A commitment with no encouragements shows no encouragement line; layout unchanged.
