# SlotOccurrence Refactor (incl. Snooze Model Cleanup) — Implementation Plan

**PRD:** none (refactor; no behavior change — agreed with 3Sauce, no separate PRD)
**Tracking:** [SlotOccurence refactor](https://www.notion.so/refactor-SnoozeSlot-3854b58e32c380f29292f98090aa34ec?source=copy_link)
**Tag**: #SlotOccurence

---

## Context

The codebase has an unnamed concept smeared across the model: **"a Slot on a specific
day"** (one concrete firing). It appears in three overlapping disguises:

1. `Slot.resolveOccurrence(on:) -> Slot?` returns a **fake `Slot`** — a non-inserted
   `@Model` with concrete `start`/`end` datetimes and a copied `id`, but still carrying
   `recurrence`/`maxCheckIns`/`snoozes` that are meaningless on a single firing.
2. `Commitment.ResolvedSlotPair = (occurrence: Slot, original: Slot)` — a tuple that exists
   _only_ to recover the real template from the fake copy (so snooze/saturation can be
   checked on `.original`).
3. `SlotSnooze` = `slot` + `psychDay` — which **is** a reference to one slot-occurrence.

This overload (`Slot` means both "recurring template" and "one firing") is the root
obscurity. It is what made the snooze model leaky: `isSnoozed` re-derives its day key from
the live slot config, so editing a slot can silently orphan a snooze.

**Decision (agreed with 3Sauce):** introduce a first-class `SlotOccurrence` value type and
converge all three disguises onto it. This subsumes the earlier narrow "frozen psychDay"
snooze cleanup — the frozen key falls out for free.

### Why no edit-cancel hook is needed (snooze)

`CommitmentFormDraft.apply(to:in:)` **deletes every existing `Slot` and recreates them** on
every save ([CommitmentFormDraft.swift:120-123]). The `Slot.snoozes` cascade-delete already
wipes all snoozes on save, so "cancel snooze on slot edit" happens for free — no new hook.

Accepted consequence (confirmed by 3Sauce): a **no-op save** (open editor, save without
changes) also clears that commitment's snoozes. Acceptable (snoozes are same-day ephemeral;
worst case one re-tap). **We add a code comment at that site documenting this.**

---

## Architecture Summary

Introduce:

```swift
/// One concrete firing of a Slot on one logical day. Value type — never persisted.
///
/// Stores only the minimal identity (`slot` + `psychDay`). `start`/`end` are **computed**
/// from the live slot on demand (cheap), so a SlotOccurrence can never carry a stale window.
struct SlotOccurrence: Equatable {
    let slot: Slot      // the template (owns recurrence, maxCheckIns, snoozes)
    let psychDay: Date  // logical/anchor day this firing belongs to

    // Computed from slot + psychDay; never stored.
    var start: Date { ... }  // resolve slot.start on psychDay
    var end: Date { ... }    // resolve slot.end on psychDay (next calendar day if cross-midnight)
}
```

- **`start`/`end` are computed, not stored** (3Sauce's call). They are cheap to derive from
  `slot` + `psychDay`, and computing on demand means an occurrence can never hold a window
  that disagrees with the live slot. The fake-`Slot` overload stored a frozen window; this
  doesn't.
- **`SlotOccurrence` enforces the recurrence guard (answers Q1).** The only constructor is
  `Slot.occurrence(on psychDay:) -> SlotOccurrence?`, which returns `nil` when
  `recurrence` excludes `psychDay`. You therefore **cannot construct an occurrence for a day
  the slot does not fire** — a "wrong psychDay" cannot enter the system through construction.
  (The only way one becomes wrong is a later recurrence edit; see the staleness decision.)
- `Slot.occurrence(on:)` replaces the fake-`Slot` `resolveOccurrence`. Window-derived
  helpers (`remainingFraction`, `timeOfDayText`, `endTime(onDayStarting:)`) move onto
  `SlotOccurrence`, since they were only ever meaningful on a resolved firing.
- `Commitment.ResolvedSlotPair` is **deleted** — `SlotOccurrence` _is_ the pair
  (`occ.slot` replaces `pair.original`; `occ` replaces `pair.occurrence`).
- `Commitment.SlotStatus.remainingSlots` changes `[Slot]` → `[SlotOccurrence]`, propagating
  to `CommitmentStatus.remainingSlots` and `CommitmentAndSlot.WithBehind.slots`.
- **`SlotSnooze` is an occurrence _reference_, not a `SlotOccurrence`.** It persists `slot`
  + frozen `psychDay` (+ `snoozedAt`). The distinction that matters is **freezing**:
  `SlotOccurrence` is transient and recomputes everything (window *and* day) from the live
  slot, whereas `SlotSnooze.psychDay` is persisted and set once at create
  (`slot.anchorDate(for: time)`), never re-derived. A snooze must *not* recompute its day —
  otherwise editing the recurrence would silently change which day was silenced. So don't
  make `SlotSnooze` hold a `SlotOccurrence`. `isSnoozed(at:)` resolves the occurrence at
  `time` and matches by `psychDay`.
- Delete `SlotSnooze.slotPsychDay`, `SlotSnooze.resolvedSlotEnd`, `SlotPsychDayError`
  (logic now on `Slot`/`SlotOccurrence`).

Producers (`SnoozeIntent`, `Current.snoozeCurrentSlot`) keep calling
`SlotSnooze.create(slot:at:in:)`. The display surfaces (Stage, Live Activity, widget) now
receive honest `SlotOccurrence` values instead of fake `Slot`s.

Cross-midnight correctness is preserved by routing day-resolution through the existing
`Slot.anchorDate`, which attributes post-midnight times to the window's start day.

---

## Design Decisions

### Introduce `SlotOccurrence` value type; delete the fake-`Slot` overload

**Decision:** model "a slot on a day" as a non-persisted `struct SlotOccurrence` and delete
`resolveOccurrence -> Slot?` and `ResolvedSlotPair`.

**Why not keep returning a resolved `Slot`?** A resolved `Slot` is a `@Model` that is never
inserted, carries irrelevant fields, and is indistinguishable by type from a template — the
root obscurity behind the snooze bug. A value type makes "this is one firing" explicit and
cheap, and is naturally `Equatable` (better for SwiftUI diffing than identity-compared
`@Model`s).

**Why not keep `[Slot]` at the display boundary?** (3Sauce chose to change it.) Converting
back to fake `Slot`s at the edge would keep the overload alive in Stage/widget/LiveActivity.
Pushing `SlotOccurrence` all the way out removes fake-`Slot` from the entire app.

**Risk:** broad surface (Commitment pipeline + 4 display surfaces + scheduler).
**Mitigation:** phase it — internal pipeline first (no public type change), then push the
type outward; each commit builds + tests green.

### `SlotSnooze` is a _frozen_ occurrence reference, not a `SlotOccurrence`

**Decision:** `SlotSnooze` persists `slot` + `psychDay` (+ `snoozedAt`). `psychDay` is set
once at create from `slot.anchorDate(for: time)` and matched as a plain stored value;
`isSnoozed` no longer reconstructs it through `slotPsychDay`.

The distinction from `SlotOccurrence` is **freezing**, not field count: `SlotOccurrence` is
transient and recomputes everything from the live slot, whereas `SlotSnooze.psychDay` is a
persisted fact, fixed at create. A snooze must *not* recompute its day — if it did, editing
the recurrence would silently change which day was silenced. So `SlotSnooze` does **not** hold
a `SlotOccurrence`; the slogan "a snooze is a silenced occurrence" is conceptual only.

**Why keep only `psychDay` (and not a fuller key)?** A slot fires at most once per logical
day, so `slot` + `psychDay` uniquely identifies the firing. The field already exists, so this
needs **no schema migration** — only how `psychDay` is computed changes.

**Risk:** cross-midnight day drift. **Mitigation:** single source of truth via
`Slot.anchorDate`; keep cross-midnight snooze tests green.

### Staleness & recurrence edits — prevented, then made harmless (answers Q1 + Q3)

**Decision:** we do **not** add active staleness handling for a persisted `psychDay` that no
longer matches the slot's recurrence/window. Two independent protections cover it:

1. **Prevented by delete-and-recreate.** Editing a slot deletes the old `Slot` and recreates
   it (`CommitmentFormDraft.apply`), so cascade-delete removes its snoozes. A recurrence edit
   (e.g. Mon/Wed/Fri → Tue/Thu) destroys the `Slot` that owned the snooze — there is no
   surviving row to be stale. This is the same mechanism that gives free snooze-cancellation.
2. **Made harmless by the defensive read guard.** `isSnoozed(at: time)` calls
   `isScheduled(on: time)` first and returns `false` if the slot no longer fires at that
   time. So even if a stale `psychDay` row somehow existed (e.g. a *future* in-place editor
   that mutates `slot.recurrence` without delete-and-recreate), it is **inert** — it can
   never match a day the slot doesn't fire, and lazy GC eventually removes it.

**Invariant to document in code:** any future in-place slot editor (one that mutates
`slot.start`/`end`/`recurrence` instead of delete-and-recreate) **must** clear that slot's
snoozes. We rely on delete-and-recreate today; a comment at `SlotSnooze`/`isSnoozed` records
this so the guard isn't mistaken for full staleness handling.

**Why not an explicit invalidation API now?** (3Sauce's call: rely on existing guards +
document.) The in-place edit path doesn't exist; adding `invalidateAll(for:)` would be
speculative. The read guard already neutralizes the only failure mode.

### No edit-cancel hook; document the no-op-save consequence

**Decision:** rely on existing delete-and-recreate; add a clarifying comment in `apply`.

**Why not gate on "actual change"?** Delete-and-recreate already over-delivers
cancellation; gating adds complexity for a benign, accepted side-effect.

---

## Major Model Changes

| Entity                                                              | Change                                                                                                                                                                                                                                                  |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **New:** `Shared/Models/SlotOccurrence.swift`                       | Value type: stores `slot` + `psychDay`; `start`/`end` are **computed** from the live slot; hosts window helpers (`remainingFraction`, `timeOfDayText`, `endTime(onDayStarting:)`, etc.).                                                                |
| `Shared/Models/Slot.swift`                                          | Add `occurrence(on:) -> SlotOccurrence?`; delete fake-`Slot` `resolveOccurrence`; promote `anchorDate` to internal; move window-only helpers to `SlotOccurrence`; rewrite `isSnoozed` to match frozen `psychDay`; `isSaturated` uses `occurrence(on:)`. |
| `Shared/Models/SlotSnooze.swift`                                    | Frozen `psychDay` via `Slot.anchorDate`; GC via `Slot.occurrence(on:)?.end`; **delete** `slotPsychDay`, `resolvedSlotEnd`, `SlotPsychDayError`. No on-disk field change.                                                                                |
| `Shared/Models/Commitment.swift`                                    | Delete `ResolvedSlotPair`; `resolvedSlotPairs`/`remainingUsableOccurrences`/`slotStarts` return/consume `[SlotOccurrence]`; `SlotStatus.remainingSlots`/`CommitmentStatus.remainingSlots` → `[SlotOccurrence]`.                                         |
| `Shared/Scheduling/CommitmentAndSlot.swift`                         | `WithBehind.slots` → `[SlotOccurrence]`; sorts/`remainingFraction` read occurrence fields.                                                                                                                                                              |
| Display surfaces                                                    | Stage (`StageView`, `Current`), `WidgetExtension/`\*, `Shared/Widget/LiveActivityRefresher.swift` read `SlotOccurrence` instead of resolved `Slot`.                                                                                                     |
| `Wilgo/Features/Notifications/SlotStartNotificationScheduler.swift` | `resolveOccurrence` call → `occurrence(on:)`.                                                                                                                                                                                                           |
| `Wilgo/Features/Commitments/Form/CommitmentFormDraft.swift`         | Comment only: delete-and-recreate cancels all snoozes on save (incl. no-op).                                                                                                                                                                            |

**No schema migration** — `SlotSnooze` field set unchanged; `SlotOccurrence` is not
persisted.

---

## Commit Plan

Simulator: iPhone 17 (iOS 26.4), UDID `4492FF84-2E83-4350-8008-B87DE7AE2588`. Run snooze/
slot tests first, then full suite (per CLAUDE.md). Each commit builds + tests green.

---

### Phase 1 — Introduce `SlotOccurrence`, migrate `Commitment` internals (no public type change)

Goal: create the type and converge the internal pipeline + `Slot` helpers onto it, while
`remainingSlots`/`WithBehind` still expose `[Slot]` (convert at the internal boundary). This
de-risks the broad change by isolating it.

#### Commit 1 — add `SlotOccurrence` + `Slot.occurrence(on:)` + move window helpers

**Create:** `Shared/Models/SlotOccurrence.swift` (struct with stored `slot` + `psychDay`,
**computed** `start`/`end`, plus `remainingFraction`, `timeOfDayText`,
`endTime(onDayStarting:)`, `endTime`).
**Modify:** `Shared/Models/Slot.swift` — add `occurrence(on:) -> SlotOccurrence?` (returns
`nil` when recurrence excludes the day — the Q1 guard); promote `anchorDate` to internal.
Keep `resolveOccurrence` temporarily (delete in Phase 2) to avoid churn.
**Create tests:** `WilgoTests/Slot/SlotOccurrenceTests.swift` — computed `start`/`end` for
normal + cross-midnight; `remainingFraction`; **excluded-day → `occurrence(on:)` returns
nil** (Q1).
_No dependents._

#### Commit 2 — migrate `Commitment` pipeline to `SlotOccurrence` internally

**Modify:** `Shared/Models/Commitment.swift` — `resolvedSlotPairs` →
`[SlotOccurrence]`; delete `ResolvedSlotPair`; `remainingUsableOccurrences`/`slotStarts`
consume occurrences (`occ.slot.isSnoozed`, `occ.slot.isSaturated`). Convert
`SlotOccurrence` → resolved `Slot` only at the `SlotStatus.remainingSlots` boundary (kept
`[Slot]` for now).
**Modify tests:** `CommitmentSlotStartsTests`, `CommitmentSlotStatus*Tests` — adjust to new
internals; behavior identical.
_Depends on Commit 1._

### Phase 2 — Push `SlotOccurrence` out to consumers; land snooze cleanup

Goal: change the public types and delete the fake-`Slot` overload + snooze date helpers.

#### Commit 3 — `remainingSlots`/`WithBehind.slots` → `[SlotOccurrence]`

**Modify:** `Commitment.swift` (`SlotStatus`/`CommitmentStatus.remainingSlots`),
`CommitmentAndSlot.swift` (`WithBehind.slots`, sorts). Remove the boundary conversion from
Commit 2.
_Depends on Commit 2._

#### Commit 4 — migrate display surfaces to `SlotOccurrence`

**Modify:** `StageView.swift`, `Current.swift`, `WidgetExtension/CurrentCommitmentWidget.swift`,
`WidgetExtension/NowLiveActivity.swift`, `Shared/Widget/LiveActivityRefresher.swift`,
`Wilgo/Features/Notifications/CatchUpReminder.swift` — read occurrence fields/helpers.
**Modify:** `SlotStartNotificationScheduler.swift` — `occurrence(on:)`.
_Depends on Commit 3._

#### Commit 5 — delete fake-`Slot` `resolveOccurrence`; clean `Slot`

**Modify:** `Slot.swift` — delete `resolveOccurrence -> Slot?`; ensure no remaining callers.
_Depends on Commit 4._

#### Commit 6 — reframe `SlotSnooze` on frozen `psychDay`; delete date helpers

**Modify:** `SlotSnooze.swift` — `create` stores `slot.anchorDate(for: time)`; GC via
`slot.occurrence(on:)?.end`; **delete** `slotPsychDay`, `resolvedSlotEnd`,
`SlotPsychDayError`. Document that `SlotSnooze` is an occurrence _reference_ (slot +
frozen psychDay, no window) and the in-place-edit invariant. **Modify:** `Slot.isSnoozed`
→ keep the `isScheduled` defensive read guard (renders stale rows inert), then match frozen
`psychDay` via `anchorDate`.
**Modify tests:** retire/fold `SlotPsychDayTests` into `SlotOccurrenceTests`; update
`SlotSnoozeCreateTests`, `SlotIsSnoozedTests`. Add a test that a snooze whose day is later
excluded by recurrence is treated as not-snoozed (read-guard inertness).
_Depends on Commit 5._

#### Commit 7 — document no-op-save snooze clearing + edit invariant

**Modify:** `CommitmentFormDraft.swift` — comment at delete-and-recreate noting it cancels
all snoozes on save (incl. no-op), and that this is the mechanism the snooze model relies on
for staleness prevention (any future in-place editor must do the same).
_Depends on Commit 6 (final semantics). Doc-only._

---

## Critical Files

| File                                        | Role                                                                        |
| ------------------------------------------- | --------------------------------------------------------------------------- |
| `Shared/Models/SlotOccurrence.swift` (new)  | The "slot on a day" value type                                              |
| `Shared/Models/Slot.swift`                  | `occurrence(on:)`, `anchorDate`, `isSnoozed`; lose fake `resolveOccurrence` |
| `Shared/Models/SlotSnooze.swift`            | Frozen-key snooze; delete duplicate date helpers                            |
| `Shared/Models/Commitment.swift`            | Pipeline + `remainingSlots` type                                            |
| `Shared/Scheduling/CommitmentAndSlot.swift` | `WithBehind.slots` type + sorts                                             |
| Display surfaces + scheduler                | Consume `SlotOccurrence`                                                    |

### Dependency Graph

```
Commit 1: add SlotOccurrence + Slot.occurrence(on:) + window helpers
    |
Commit 2: Commitment pipeline → SlotOccurrence (internal; remainingSlots still [Slot])
    |
Commit 3: remainingSlots / WithBehind.slots → [SlotOccurrence]
    |
Commit 4: display surfaces + scheduler → SlotOccurrence
    |
Commit 5: delete fake-Slot resolveOccurrence
    |
Commit 6: SlotSnooze frozen psychDay; delete slotPsychDay/resolvedSlotEnd
    |
Commit 7: doc no-op-save consequence
```

Fully sequential — each commit narrows the surface the next touches.

### Out of scope (deferred — 3Sauce will review separately)

- The two consumers' two-reference-time design and the three near-identical `*WithBehind`
  helpers in `CommitmentAndSlot`. Left as-is; 3Sauce reviews after this refactor.
