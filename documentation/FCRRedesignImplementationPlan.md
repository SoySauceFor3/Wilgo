# FCR Redesign + PT Reframe — Implementation Plan

**PRD:** [FCR Redesign + PT Reframe](https://www.notion.so/3684b58e32c3804b921df8e39b4bfae7)  
**Tracking:** [FCR redesign](https://www.notion.so/FCR-redesign-3764b58e32c38022a0efea1122f22d93)  
**Tag:** `#FCRRedesign`

---

## Context

This plan covers three tightly coupled changes:

1. **Remove InsOnly mode** — `TargetMode.inspirationOnly` deleted entirely
2. **Reframe PT** — from currency/compensation mechanic to pure wins journal; 1 PT required per failed cycle in FCR
3. **Redesign FCR** — new single-screen card UI with purposeful stop (failed) + celebration (passed), backfill via reused components, new `CycleRecord` persistence, streak summary

The mockup is at `documentation/FCRMockup.html`.

---

## Architecture Summary

### What's Removed
- `TargetMode.inspirationOnly` case and all associated logic
- `PositivityTokenStep` (the old step 2 of FCR)
- `PositivityTokenCompensator` and `AfterPositivityTokenReportBuilder`
- `PositivityTokenUsageSummary`
- `PositivityToken.status` / `.used` / `.expired` — tokens are now simple journal entries
- Monthly PT cap
- PT mint capacity formula (`checkIns - tokensCreated`)
- `CurrentCycleDialogModifier` and `CurrentCycleDialogContent` (used `until` to set InsOnly for current cycle)
- `WeekStartChangeHandler` InsOnly snap logic
- `CommitmentFormFields` InsOnly date picker UI
- `CommitmentFormDraft.inspirationOnlyUntilValidation`

### What's Added
- **`CycleRecord`** — new SwiftData model, append-only, written when FCR closes
- **`FCRCycleCardView`** — new expandable card per cycle in FCR
- **`InsOnlyCycleOutcome`** enum — `excused | punished | letGo | other` label on failed cycles
- **PT as wins journal** — `PositivityToken` loses `status`/`dayOfStatus`; becomes a plain journal entry with `reason` + `createdAt`
- **Inline PT minting in FCR** — mint sheet inside FCR if not enough active PTs
- **Streak summary** — computed from check-in data, shown on failed cycle cards

### Reused Components (do not rebuild)
- `CommitmentHeatmapInfoCard` — history expansion inside each cycle card, toggled by 📅 icon
- `BackfillSheet` — opened from "Add check-in" in InfoCard, clamped to cycle date range
- `CheckInUndoBannerOverlay` + `CheckInUndoManager` — undo toast after backfill

---

## Design Decisions

### Remove InsOnly entirely (not just the end date)
The FCR redesign (purposeful stop + excused/let-go labels) absorbs everything InsOnly was trying to do. Keeping the mode adds complexity with no remaining benefit. See InsOnly PRD for original removal rationale.

### CycleRecord is append-only, no retroactive reconciliation
Cycle changes (weekly → monthly) may create gaps. Accepted. History reflects what was reported at the time.

### Streak summary uses check-in ground truth, not CycleRecord
`CycleRecord` labels (excused/punished) are not layered onto streak counts — cycle boundary changes make mapping unreliable. Raw check-in counts against cycle boundaries are the source of truth.

### PT becomes a plain journal entry with an optional back-reference to CycleRecord
Removing `status` / `dayOfStatus` / monthly cap simplifies the model significantly. The only mechanical role PT now plays in FCR is as a required gate: 1 PT consumed per failed cycle.

The linkage is stored bidirectionally:
- `CycleRecord.consumedPTID: UUID?` — points from the cycle to the PT used
- `PositivityToken.consumedByCycleRecord: CycleRecord?` — SwiftData relationship back to the cycle record (nil = free journal entry, non-nil = consumed by a failed cycle)

This replaces the old `status` enum — "active vs consumed" is simply `consumedByCycleRecord == nil`. The back-reference is stored for future use but the wins journal UI does not currently display the FCR linkage (decided: keep UI clean, data rich).

---

## Major Model Changes

| Entity | Change |
|---|---|
| `Shared/Models/TargetMode.swift` | Delete `inspirationOnly` case entirely. Custom Codable to handle old stored data gracefully (map to `.on`). Remove all associated methods/errors. |
| `Shared/Models/Commitment.swift` | Remove `isInsOnlyRemindersEnabled`. No other changes. |
| `Shared/Models/PositivityToken.swift` | Remove `status: Status`, `dayOfStatus: Date?`. Add `consumedByCycleRecord: CycleRecord?` (nullify delete rule — deleting a CycleRecord frees the PT back to the journal). Token becomes `id + reason + createdAt + consumedByCycleRecord`. |
| **New:** `Shared/Models/CycleRecord.swift` | New SwiftData `@Model`. Fields: `id`, `commitment` (relationship, nullify), `cycleStart`, `cycleEnd`, `outcome` (enum: passed/excused/punished/letGo/other), `reflectionText` (String?), `emojiReactions` ([String]), `consumedPT: PositivityToken?` (relationship, nullify — inverse of `consumedByCycleRecord`), `recordedAt`. Append-only. |
| `Wilgo/Features/Commitments/FinishedCycleReport/Models.swift` | Remove `PositivityTokenUsageSummary`. Remove `consumedPTReasons` from `CycleReport`. Add `failureOutcome: InsOnlyCycleOutcome?`, `reflectionText: String?`, `consumedPTID: UUID?`, `emojiReactions: [String]`. |
| `Wilgo/WilgoApp.swift` | Add `CycleRecord.self` to schema. Remove InsOnly background task registration. |

---

## Roadmap

The work naturally splits into 5 phases. Phases 1–2 are foundational and must complete before the others. Phases 3–5 can be parallelized after Phase 2.

---

### Phase 1 — Remove InsOnly (foundation for everything)

**Goal:** Eliminate `TargetMode.inspirationOnly` from the codebase. Everything downstream either simplifies or stops compiling — that's intentional, it surfaces all call sites.

#### Commit 1A — refactor: remove InsOnly from TargetMode and all call sites `#FCRRedesign`

**Modify:** `Shared/Models/TargetMode.swift`
- Delete `inspirationOnly` case
- Add custom `Codable` `init(from:)` that maps old stored `inspirationOnly` data → `.on`
- Simplify/delete: `effectiveMode(on:)`, `effectiveMode(from:to:)`, `overlapsInspirationOnlyInterval`, `normalized`, `partialInspirationOnlyOverlap`

**Modify:** `Shared/Models/Commitment.swift`
- Remove `normalizeMode(afterReportedThrough:)` (no-op without InsOnly)

**Modify:** `Wilgo/Features/Settings/WeekStartChangeHandler.swift`
- Remove `InspirationOnlyCommitmentInfo`, `oldUntil/newUntil/isExpiredAfterSnap`
- Simplify `previewChanges` and `apply` — no InsOnly snapping

**Modify:** `Wilgo/Features/Settings/SettingsView.swift`
- Remove `inspirationOnlyUntilLabel` helper

**Modify:** `Wilgo/Features/Commitments/SingleCommitment/CommitmentDetailView.swift`
- Collapse InsOnly branch of `targetModeDetailText` — unreachable, delete

**Modify:** `Wilgo/Features/Commitments/SingleCommitment/CommitmentRowView.swift`
- Collapse InsOnly branch of `targetSummaryText` — unreachable, delete

**Delete:** `Wilgo/Features/Commitments/CurrentCycleDialogModifier.swift`
- This entire feature only existed to set `until: cycleEnd` on InsOnly. Gone.

**Modify:** `Wilgo/Features/Commitments/Form/AddCommitmentView.swift`
- Remove `CurrentCycleDialogModifier` usage

**Modify:** `Wilgo/Features/Commitments/Form/EditCommitmentView.swift`
- Remove `CurrentCycleDialogModifier` usage

**Modify:** `Wilgo/Features/Commitments/Form/CommitmentFormFields.swift`
- Remove InsOnly date picker, Forever toggle, related bindings

**Modify:** `Wilgo/Features/Commitments/Form/CommitmentFormDraft.swift`
- Remove `inspirationOnlyUntilValidation`, simplify `canSave`, `reanchorInspirationOnlyTarget`

**Update tests:** Delete all `until`-bearing tests in `TargetModeTests`, `CommitmentFormDraftTests`, `WeekStartChangeHandlerTests`, `CommitmentSlotStatusInspirationOnlyTests`

**Manual verification:** Launch on iPhone 17 simulator. App must launch without crash. Existing InsOnly commitments must open without crash (custom decoder maps them to `.on`).

---

### Phase 2 — PT model simplification + CycleRecord introduction

**Goal:** Simplify `PositivityToken` to a plain journal entry. Introduce `CycleRecord` SwiftData model. Schema version bump.

#### Commit 2A — refactor: simplify PositivityToken to plain journal entry `#FCRRedesign`

**Modify:** `Shared/Models/PositivityToken.swift`
- Remove `status: Status` enum and property
- Remove `dayOfStatus: Date?`
- Add `consumedByCycleRecord: CycleRecord?` relationship (nullify — deleting a CycleRecord frees the PT)
- Add custom `Codable` to handle old stored tokens with `status`/`dayOfStatus` (ignore those fields on decode)
- Note: "active vs consumed" is now simply `consumedByCycleRecord == nil`

**Modify:** `Wilgo/Features/PositivityToken/ListView.swift`
- Remove used/expired grouping sections — show all tokens as a flat journal list, newest first
- Remove "monthly budget remaining" summary
- Remove capacity indicator

**Modify:** `Wilgo/Features/PositivityToken/PositivityTokenMinting.swift`
- Delete entirely or gut — mint capacity formula (`checkIns - tokensCreated`) no longer applies
- Minting is now unrestricted

**Delete:** `Wilgo/Features/Commitments/FinishedCycleReport/PositivityTokenCompensator.swift`
**Delete:** `Wilgo/Features/Commitments/FinishedCycleReport/PositivityTokenStep.swift`
**Delete:** `Wilgo/Features/Commitments/FinishedCycleReport/PositivityTokenPage.swift`

**Update tests:** Delete `PositivityTokenMintingTests`, `PositivityTokenCompensatorTests`

#### Commit 2B — feat: add CycleRecord SwiftData model `#FCRRedesign`

**Create:** `Shared/Models/CycleRecord.swift`

```swift
enum CycleOutcome: String, Codable {
    case passed
    case excused
    case punished
    case letGo
    case other
}

@Model final class CycleRecord {
    @Attribute(.unique) var id: UUID
    @Relationship(deleteRule: .cascade) var commitment: Commitment
    var cycleStart: Date
    var cycleEnd: Date
    var outcome: CycleOutcome
    var reflectionText: String?
    var emojiReactions: [String]
    var consumedPTID: UUID?
    var recordedAt: Date
}
```

**Modify:** `Wilgo/WilgoApp.swift`
- Add `CycleRecord.self` to `Schema([...])`

**Update test schemas:** Add `CycleRecord.self` to all `makeContainer()` functions in test files.

**Create:** `WilgoTests/CycleRecord/CycleRecordModelTests.swift`
- CycleRecord persists with correct fields
- Deleting commitment cascades to CycleRecord
- `outcome` round-trips Codable

**Manual verification:** App launches, no crash, existing data intact.

---

### Phase 3 — New FCR UI (after Phase 1 + 2)

**Goal:** Replace the two-step FCR with the new single-screen card-based UI.

#### Commit 3A — feat: FCRCycleCardView stub with expand/collapse `#FCRRedesign`

**Create:** `Wilgo/Features/Commitments/FinishedCycleReport/FCRCycleCardView.swift`

Stub with:
- Collapsed state: status dot, title, date, badge, chevron
- Expanded state: card header with badge + 📅 icon + ↑ minimize icon
- 📅 icon toggles `CommitmentHeatmapInfoCard` inline (pass `onAddCheckIn` → triggers `BackfillSheet`)
- `CheckInUndoBannerOverlay` wired up for backfill undo
- Live count badge updates when check-ins change
- Auto-flip: if check-ins hit target → switch to passed state; if undo drops below target → switch back to failed state
- Failed state: streak summary line + label pills + required textbox + PT row (stub: always "needed")
- Passed state: optional emoji reaction row
- Passed cycles: start collapsed, no required fields

#### Commit 3B — feat: wire FCRCycleCardView into new FinishedCycleReportView `#FCRRedesign`

**Modify:** `Wilgo/Features/Commitments/FinishedCycleReport/FinishedCycleReportView.swift`
- Replace two-step navigation with single scrollable list of `FCRCycleCardView`
- Title: "Cycle Report" (not date-based)
- Nav bar: Cancel (left) + Done (right, disabled until all failed cycles complete)
- Done button logic: all failed cycles have label + reflectionText + PT consumed
- Remove `preTokenReportForTokenStep` state
- Remove `PositivityTokenStep` navigation destination

**Modify:** `Wilgo/Features/Commitments/FinishedCycleReport/CheckInSummaryStep.swift`
- Remove entirely or gut — replaced by `FCRCycleCardView`

**Delete:** old `CheckInSummaryPage.swift` (UI replaced)

#### Commit 3C — feat: streak summary computation `#FCRRedesign`

**Create:** `Wilgo/Features/Commitments/FinishedCycleReport/StreakSummary.swift`

```swift
enum StreakSummary {
    static func compute(for commitment: Commitment, beforeCycleEnd: Date) -> String?
    // Priority:
    // 1. "X consecutive failed cycles" (if 2+)
    // 2. "First failure after X consecutive wins" (if streak just broke)
    // 3. "Failed X of the last Y cycles" (fallback, no clean streak)
    // 4. "No passed cycles in X months" (2+ month drought)
    // Returns nil if none apply (e.g. first ever cycle)
}
```

Computed from check-in data against cycle boundaries — no dependency on `CycleRecord`.

**Create:** `WilgoTests/FinishedCycleReport/StreakSummaryTests.swift`
- Each of the 4 cases
- Nil when first cycle
- Correct threshold (2+ for consecutive)

---

### Phase 4 — PT gate in FCR + inline minting (after Phase 2 + 3)

**Goal:** Wire the PT requirement into the FCR card. Each failed cycle must consume 1 PT before Done unlocks.

#### Commit 4A — feat: PT consumption gate in FCRCycleCardView `#FCRRedesign`

**Modify:** `FCRCycleCardView.swift`
- PT row shows "Covered" (green) if a PT is assigned, "Needed" (red) if not
- "Needed" row has "+ Mint one now" button
- Tapping opens inline mint sheet (text field + "Save & use as PT")
- On save: create new `PositivityToken`, record its `id` as `consumedPTID` in the card's draft state
- If user already has active PTs with no cycle assigned: auto-assign oldest available

**Modify:** `Wilgo/Features/PositivityToken/AddView.swift`
- Keep standalone minting flow unchanged — minting from PT tab still works

#### Commit 4B — feat: write CycleRecord on FCR close `#FCRRedesign`

**Modify:** `FinishedCycleReportView.swift`
- On Done tap: for each cycle card, write a `CycleRecord` to SwiftData
- Passed cycles: `outcome = .passed`, `emojiReactions` from card state, `consumedPTID = nil`
- Failed cycles: `outcome` from selected label, `reflectionText` from textbox, `consumedPTID` from PT assigned
- Advance watermark as before

---

### Phase 5 — Cleanup + test coverage (after all phases)

#### Commit 5A — refactor: remove dead FCR code + update all tests `#FCRRedesign`

- Delete `PositivityTokenUsageSummary` from `Models.swift`
- Remove `consumedPTReasons` from `CycleReport`
- Delete `PreTokenReportBuilder` references to InsOnly `effectiveMode`
- Update `FinishedCycleReportBuilderTests`, `FinishedCycleReportPresentationStateTests`
- Update `PositivityTokenModelTests` for simplified model

#### Commit 5B — feat: PT wins journal view polish `#FCRRedesign`

**Modify:** `Wilgo/Features/PositivityToken/ListView.swift`
- Clean flat journal list, grouped by month
- Each entry: reason text + date
- No status grouping, no budget display
- Keep minting flow (+ button)

---

## Dependency Graph

```
Phase 1 — Remove InsOnly (1A)
    │
    ├── Phase 2A — Simplify PT model          [parallel after 1A]
    ├── Phase 2B — Add CycleRecord model      [parallel after 1A]
    │
    └── (wait for 2A + 2B)
            │
            ├── Phase 3A — FCRCycleCardView stub       [parallel]
            ├── Phase 3B — New FCRView                 [after 3A]
            ├── Phase 3C — StreakSummary               [parallel]
            │
            └── (wait for 3A + 3B)
                    │
                    ├── Phase 4A — PT gate in card     [parallel]
                    ├── Phase 4B — Write CycleRecord   [after 4A]
                    │
                    └── Phase 5 — Cleanup + polish     [after all]
```

---

## Critical Files

| File | Role |
|---|---|
| `Shared/Models/TargetMode.swift` | Phase 1 foundation — everything compiles after this |
| `Shared/Models/PositivityToken.swift` | Phase 2 simplification |
| `Shared/Models/CycleRecord.swift` (new) | Phase 2 new model |
| `FinishedCycleReport/FCRCycleCardView.swift` (new) | Phase 3 core UI |
| `FinishedCycleReport/FinishedCycleReportView.swift` | Phase 3 orchestration |
| `FinishedCycleReport/StreakSummary.swift` (new) | Phase 3 computation |
| `documentation/FCRMockup.html` | UI reference — check before implementing any UI |

---

## Open Questions Before Starting

- [ ] Tracking link from 3Sauce for commit messages
- [ ] Does `PreTokenReportBuilder` need to be renamed/refactored or just updated in place?
- [ ] Should passed cycles that the user never expanded also get a `CycleRecord` written? (Lean: yes, with `outcome = .passed` and empty emoji reactions)
