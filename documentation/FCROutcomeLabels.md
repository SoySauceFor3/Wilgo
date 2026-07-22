# FCR Outcome Labels & Per-Outcome Requirements

**Date:** 2026-07-19
**PRD:** N.A.
**Tracking:** [https://app.notion.com/p/For-FCR-add-Intented-for-failed-cmmt-cycles-and-change-the-PT-s-requirement-to-be-not-EVERY-fai-3a04b58e32c3805d8479d0d76087955f?source=copy_link](https://app.notion.com/p/For-FCR-add-Intented-for-failed-cmmt-cycles-and-change-the-PT-s-requirement-to-be-not-EVERY-fai-3a04b58e32c3805d8479d0d76087955f?source=copy_link)
**Tag:** `#FCROutcomeLabels`

---

## Problem

The Finished Cycle Report (FCR) currently gates every failed cycle behind a
uniform requirement: pick a label + assign exactly one Positivity Token (PT),
plus a written reflection _only_ when the label is `.other`
([FCRCycleCardState.swift:50](../Wilgo/Features/Commitments/FinishedCycleReport/FCRCycleCardState.swift#L50)).

Two pain points:

1. **No "planned fail" label.** All existing labels are reactive
   (excused / punished / let go). Test commitments and intentional throwaway
   cycles have no honest home and get mislabeled.
2. **A PT is required for _every_ failed cycle.** Writing a wins-journal entry
   for every single miss is intimidating and turns closing a report into a
   chore — the opposite of the wins-journal's intent.

## Goals

- Add a first-class **Intended** outcome for planned/test fails.
- Replace the uniform "PT + label + conditional note" gate with a
  **per-outcome** requirement matrix, so friction matches the emotional stakes
  of each label.
- Remove the redundant **Other** catch-all; **Move on** becomes the true
  neutral catch-all.
- Add a **"?" help affordance** explaining the labels.

## Non-goals

- No change to passed-cycle behavior (celebration/emoji reactions unchanged).
- No change to PT auto-assignment mechanics ([FCRPTAssignment.swift](../Wilgo/Features/Commitments/FinishedCycleReport/FCRPTAssignment.swift))
  beyond _which_ cycles require a PT.
- No global user-facing config toggle. (Considered and rejected — see
  Alternatives.)

---

## The core design: an accountability model

Every failed cycle needs **exactly one form of accountability**, matched to the
label the user picks. This principle drives the whole requirement matrix:

- If the commitment has a **penalty** the user paid → **Punished** → the
  _payment_ is the accountability → reflection optional.
- If the commitment has **no penalty** → **Move on** → the _reflection_ is the
  accountability (its substitute for a penalty) → reflection required.
- **Intended** / **Excused** → the user asserts no accountability is warranted
  (planned, or justified) → nothing required.

### Outcome labels (final set — 4 labels, `.other` removed)

| Label        | Meaning                                                     |
| ------------ | ----------------------------------------------------------- |
| **Intended** | Planned / test / throwaway fail. Zero sting.                |
| **Excused**  | A legitimate reason justified the miss (sick, emergency).   |
| **Move on**  | No plan, no reason, no penalty — acknowledge and continue.  |
| **Punished** | The user imposed a consequence (real-life, penalty or not). |

`.other` is removed. `Move on` (renamed from the old `.letGo` "Let go") is the
honest catch-all: "none of the above."

### Requirement matrix

| Label        | Reflection   | PT required | Accountability source      |
| ------------ | ------------ | ----------- | -------------------------- |
| **Intended** | Optional     | ❌ No       | none warranted (planned)   |
| **Excused**  | Optional     | ❌ No       | none warranted (justified) |
| **Move on**  | **Required** | ✅ Yes      | the reflection             |
| **Punished** | Optional     | ✅ Yes      | the penalty already paid   |

Notes:

- The reflection field is **always present** under every label (an optional
  free-text note), matching current behavior. It is only _required_ for
  **Move on**.
- **All four labels are always selectable**, regardless of whether the
  commitment has a `punishment` set. The `punishment` field is only a
  pre-written reminder; real-life consequences can be improvised, so the app
  must not presume the user did/didn't punish themselves.
- A card is **complete** (FCR can close) when: passed, OR
  its label's requirements are met (PT assigned if required; reflection
  non-empty if required).

### Label rename: `.letGo` → `.moveOn`

"Let go" was doing double duty as a vague fallback. "Move on" makes its
structural role explicit: the neutral, no-penalty exit. This is a rename of the
existing case plus its display string, not a new concept.

---

## Model changes

`CycleOutcome` (in [Shared/Models/CycleRecord.swift](../Shared/Models/CycleRecord.swift#L4)):

- **Add** `case intended`.
- **Rename** `case letGo` → `case moveOn`.
- **Remove** `case other`.

`CycleOutcome` is `String`-backed and persisted on `CycleRecord`. Removing the
`letGo`/`other` cases is a **persisted enum change**: existing on-disk rows carry
raw values (`"letGo"`, `"other"`) that no longer map to a case.

**Migration decision (2026-07-20):** a **one-time wipe** of all `CycleRecord`
rows, guarded by a `UserDefaults` flag. Rationale: FCR/`CycleRecord` is
unreleased to `main` (branch `RedoFCR`), so 3Sauce is fine starting the cycle
history fresh. This sidesteps the SwiftData hazard that loading a row with an
unknown enum raw value can crash on fetch — a *read*-based migration hits a
chicken-and-egg problem (you must materialize the dead enum to fix it), whereas a
batch delete operates without materializing `outcome`.

- On launch, if a `UserDefaults` flag (e.g. `didWipeLegacyCycleRecords_v2`) is
  unset: `try context.delete(model: CycleRecord.self)`, then set the flag. Runs
  once per install.
- Side effect (acceptable/intended): deleting CycleRecords nullifies
  `PositivityToken.consumedByCycleRecord`, so any consumed PTs return to the
  wins journal as free tokens. Commitments are untouched (we delete only
  CycleRecords).
- The `CycleOutcome` `Codable` decoder that maps legacy raws is therefore **not**
  the migration mechanism (SwiftData does not route loads through `Codable`); it
  is at most harmless insurance for any JSON path. Once the wipe ships, no legacy
  raws survive.

**Rejected alternatives:** launch-time read-migration loop (can crash on the
fetch it needs); `SchemaMigrationPlan` custom stage (correct but introduces
versioned-schema infra this repo has none of — overkill for unreleased data);
raw-`String`-column + computed enum (safe and simple, but 3Sauce preferred a
clean wipe over carrying a lazy-mapping property forever).

`CycleRecordBuilder` / `FCRPTAssignment` gating updates so PT is only assigned
to cycles whose selected label requires one (Move on, Punished), rather than
all failed cycles.

---

## Per-outcome requirement logic (where it lives)

Introduce a single source of truth for the matrix, e.g. computed properties on
`CycleOutcome`:

```swift
extension CycleOutcome {
    var requiresPT: Bool { self == .moveOn || self == .punished }
    var requiresReflection: Bool { self == .moveOn }
}
```

`FCRCycleCardState.isComplete` and `isReflectionRequired`
([FCRCycleCardState.swift:50-62](../Wilgo/Features/Commitments/FinishedCycleReport/FCRCycleCardState.swift#L50-L62))
are rewritten to consult these, replacing the hardcoded `.other` special-case
and the unconditional `hasAssignedPT` requirement.

---

## UI changes

In [FCRCycleCardView.swift](../Wilgo/Features/Commitments/FinishedCycleReport/FCRCycleCardView.swift):

1. **Label pills:** `selectableOutcomes` becomes
   `[.intended, .excused, .moveOn, .punished]` (order = lightest → heaviest
   accountability). Display names & tints for `.intended` (new) and `.moveOn`
   (renamed) added to the `CycleOutcome` display extension.
2. **Reflection header:** "WRITE SOMETHING (REQUIRED)" shows when the selected
   label `requiresReflection` (i.e. Move on), else "(OPTIONAL)".
3. **PT row:** only shown/required when the selected label `requiresPT`.
   For Intended/Excused, the PT row is hidden and the card can close on the
   label alone.
4. **"?" help affordance:** a single "?" button next to the
   "HOW ARE YOU CLOSING THIS?" header opens **one popover** listing all four
   labels, each with a one-line explanation including whether it needs a PT
   and/or reflection.

---

## Help popover copy (draft)

> **Intended** — You meant for this to fail (e.g. a test run). Nothing required.
> **Excused** — A real reason got in the way. Nothing required.
> **Move on** — No reason, no penalty. Jot down why, then move on. _(note required)_
> **Punished** — You took a consequence for the miss. Add a win to balance it. _(PT required)_

_(Copy to be refined during implementation.)_

---

## Testing

- `CycleOutcome.requiresPT` / `requiresReflection` unit tests — all four cases.
- `FCRCycleCardState.isComplete` matrix tests:
  - Intended → complete on label alone.
  - Excused → complete on label alone.
  - Move on → incomplete without reflection; incomplete without PT; complete
    with both.
  - Punished → incomplete without PT; complete with PT (reflection optional).
- Flip-to-passed still clears failure fields (existing behavior preserved).
- `FCRPTAssignment` only assigns PTs to Move on / Punished cycles.
- Migration/decoding: legacy `"letGo"` and `"other"` raw values decode to
  `.moveOn`, reflection preserved.
- `FCRCompletion.canClose` across mixed states.

---

## Alternatives considered

**Global config toggle ("require a PT for every failed cycle" on/off).**
Rejected: risks quietly undoing the deliberate wins-journal-per-fail design and
is a way of avoiding a real decision. The per-outcome matrix ties the
requirement to _meaning_ instead.

**Keep "Let go" as-is + add Intended + keep Other.**
Rejected: three labels (Intended / Excused / Let go / Other) would all blur into
"this is fine, close it." Renaming Let go → Move on and dropping Other yields a
clean, exhaustive partition.

**Remove Other with no free-text on fails.**
Rejected: would lose the ability to write a reflection on a failed cycle. Kept
the always-optional note under every label instead.

**Gate "Punished" on the** `punishment` **field being set.**
Rejected: `punishment` is only a pre-written reminder; users can improvise
real-life consequences. Hiding the label would have the app presume facts it
can't know.

---

# Implementation Plan

## Architecture Summary

`CycleOutcome` (a `String`-backed `Codable` enum persisted on `CycleRecord`)
gains `intended`, renames `letGo`→`moveOn`, and drops `other`. Two computed
properties on `CycleOutcome` — `requiresPT` and `requiresReflection` — become
the **single source of truth** for the requirement matrix above.

`FCRCycleCardState.isComplete` / `isReflectionRequired` are rewritten to consult
those properties, replacing the hardcoded `.other` special-case and the
unconditional `hasAssignedPT` gate. The card view shows the PT row and the
reflection "(REQUIRED)"/"(OPTIONAL)" state driven by the selected label, and
adds the "?" popover.

Because the enum is persisted, legacy raw values `"letGo"` and `"other"` must
still decode. We handle this at **decode time** via a custom
`init(from:)` mapping so no stored-data rewrite is required.

**Ordering constraint (per CLAUDE.md):** UI-facing changes are prioritized so
3Sauce can manually verify on-device. The enum change is a hard dependency for
everything, so it comes first (kept minimal and self-contained, Commit 1), then
UI (Commit 2), then the gating/assignment plumbing (Commit 3).

---

## Design Decisions

### Single source of truth for the requirement matrix

**Decision:** Put `requiresPT` and `requiresReflection` as computed properties
on `CycleOutcome` in `Shared/Models/CycleRecord.swift`, read by both
`FCRCycleCardState` and the card view.

**Why not inline the rules in `FCRCycleCardState`?** The view also needs to know
(to show/hide the PT row and the reflection-required label). Duplicating the
matrix in two places invites drift. One enum-level definition keeps view and
state in lockstep and is trivially unit-testable.

**Risk:** business logic living on a model enum. Mitigation: it is pure/derived
(no state), fully unit-tested, and documented as the matrix source of truth.

### Legacy raw-value migration via decode mapping

**Decision:** Map `"letGo"` → `.moveOn` and `"other"` → `.moveOn` at decode
time. Preserve each record's existing `reflectionText`.

**Why not a data-rewrite migration pass?** SwiftData lightweight migration can't
express "rename+merge enum raw values" declaratively, and a manual rewrite pass
is riskier (touches every historical record, needs its own on-device
verification). Decode-time mapping means old rows read back as `.moveOn` with
zero writes; they normalize on next save. `Other` records keep their note, which
now reads naturally under Move on.

**Risk:** an old app reading a new `"moveOn"`/`"intended"` value would fail —
acceptable (no downgrade path supported). Mitigation: decode unit tests for both
legacy raw values.

### Always-selectable labels (no penalty gating)

**Decision:** All four labels always shown, regardless of `Commitment.punishment`.

**Why not hide Punished when no penalty is set?** `punishment` is a pre-written
reminder, not the enforcement. Users improvise real consequences. Gating would
have the app assert facts it can't know. See Alternatives above.

---

## Major Model Changes

| Entity                                                   | Change                                                                                                                                     |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `Shared/Models/CycleRecord.swift`                        | `CycleOutcome`: add `intended`, rename `letGo`→`moveOn`, remove `other`; add `requiresPT` / `requiresReflection`; custom decode mapping for legacy `"letGo"`/`"other"` |
| `Wilgo/.../FCRCycleCardState.swift`                      | `isComplete` / `isReflectionRequired` rewritten to use the matrix                                                                          |
| `Wilgo/.../FCRCycleCardView.swift`                       | `selectableOutcomes` new set/order; `.intended`/`.moveOn` display+tint; PT row conditional; reflection-required conditional; "?" popover; remove inline mint textbox — button now opens the shared sheet |
| `Wilgo/.../FinishedCycleReportView.swift`                | Parent-owned single `pendingDraft` + `mintTarget`; one shared mint `.sheet`; reconcile PT assignments on outcome-change; broaden release rule to "no longer `requiresPT`"; keep released/minted tokens |
| `Wilgo/.../CycleRecordBuilder.swift`                     | Only attach a consumed PT for outcomes that `requiresPT`                                                                                   |
| `Wilgo/.../FCRPTAssignment.swift`                        | Auto-assign PTs only to failed cycles whose outcome `requiresPT`                                                                           |

No SwiftData `Schema([...])` change (no new/removed `@Model` type — `CycleRecord`
is already registered). No new test-container schema edits required.

---

## Commit Plan

Four phases. Phase 1 lands the enum + matrix (shared foundation). Phase 2 builds
the FCR card UI **on the shared-mint-sheet architecture from the start** (no
throwaway inline box). Phase 3 owns the mint **draft** behavior (single shared
pending draft, carry-over, consume-on-save). Phase 4 tightens PT
assignment/release gating behind the UI. Phase 5 is cleanup.

Each commit is self-contained, builds, keeps existing tests green, and ships its
own unit tests. UI-facing commits are ordered first so 3Sauce can verify
on-device before the deeper plumbing.

**Why the shared mint sheet is baked in, not retrofitted:** the mint draft is a
*single* pending value that carries across cards (A→B edit→A shows the latest
text) and must survive a card's PT row being hidden on label switch. Per-card
`@State mintText`/`isMinting` can represent neither. So Commit 2 builds the
"+ Mint one now" button to open one parent-owned shared sheet immediately — we
never build the inline textbox just to delete it.

---

### Phase 1 — Enum + requirement matrix + legacy wipe (foundation)

Goal: the `CycleOutcome` shape, the matrix source-of-truth, and a guarded
one-time wipe of legacy `CycleRecord` rows. Everything else depends on this.

#### Commit 1 — model: add Intended, rename Let go→Move on, drop Other; add requirement matrix + decoder (DONE: `3ab6574`)

**Modify:** `Shared/Models/CycleRecord.swift`

```swift
enum CycleOutcome: String, Codable {
    case passed, excused, punished, moveOn, intended

    /// A Positivity Token (a wins-journal entry) is required to close the cycle.
    var requiresPT: Bool { self == .moveOn || self == .punished }
    /// A written reflection is required to close the cycle.
    var requiresReflection: Bool { self == .moveOn }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "letGo", "other": self = .moveOn   // legacy → new catch-all
        default:
            guard let v = CycleOutcome(rawValue: raw) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown CycleOutcome raw value: \(raw)"))
            }
            self = v
        }
    }
}
```

**Create:** `WilgoTests/FinishedCycleReport/CycleOutcomeMatrixTests.swift`
Tests:

- `requiresPT`: true for `.moveOn`, `.punished`; false for `.intended`,
  `.excused`, `.passed`.
- `requiresReflection`: true only for `.moveOn`.
- Decoding legacy raw `"letGo"` → `.moveOn`; `"other"` → `.moveOn`.
- Decoding `"intended"`/`"moveOn"`/`"excused"`/`"punished"`/`"passed"`
  round-trip.
- Decoding an unknown raw value throws.

Note (post-implementation): the `Codable` decoder is **insurance only** — SwiftData
does not route model loads through `Codable`, so legacy on-disk raws are handled
by the wipe in Commit 1b, not this decoder.

**Dependencies:** none. Blocks all other commits.

---

#### Commit 1a — fix: latent cascade bug (deleting a CycleRecord deleted its Commitment)

**Discovered while building Commit 1b's wipe** (its regression test caught it):
`CycleRecord.commitment` was declared `@Relationship(deleteRule: .cascade)`, and
its code comment misdescribed the effect. A `.cascade` rule on the *child→parent*
side means **deleting a CycleRecord deletes its Commitment** — so the Commit 1b
wipe (`delete(model: CycleRecord.self)`) would have deleted **every commitment
that had a cycle record**. This is a pre-existing latent bug, not introduced by
this feature, but the wipe would have triggered it catastrophically.

**Modify:** `Shared/Models/CycleRecord.swift` — change `commitment`'s rule from
`.cascade` to `.noAction`; keep `commitment` non-optional (a record always has a
commitment; `.noAction` is safe because the CycleRecord — the referrer — is the
thing being deleted, leaving no dangling reference). Correct the misleading
comment. `Commitment.cycleRecords` (`.cascade`, inverse) is **unchanged** — that
direction is intended.

**Test:** deleting a CycleRecord leaves its Commitment intact (direct regression
guard); the existing Commitment→CycleRecords cascade still holds.

**Dependencies:** Commit 1. Must land **before** Commit 1b.

---

#### Commit 1b — migration: one-time guarded wipe of legacy CycleRecord rows

**Why:** existing on-disk `CycleRecord` rows carry `outcome` raws `"letGo"` /
`"other"` that no longer map to a case; SwiftData can crash when it materializes
such a row on fetch. FCR/`CycleRecord` is unreleased to `main`, so we start the
cycle history fresh with a one-time wipe rather than a read-migration (which
would hit the fetch it needs to fix). Decided 2026-07-20.

**Modify:** `Wilgo/WilgoApp.swift` (or a small dedicated helper it calls once at
container setup / first `.onAppear`):

- Guard on a `UserDefaults` flag, e.g. `didWipeLegacyCycleRecords_v2`.
- If unset: on the main context, `try context.delete(model: CycleRecord.self)`
  and `try context.save()`, then set the flag `true`.
- Runs exactly once per install; a no-op on every subsequent launch.
- Do this **before** any view fetches `CycleRecord` (so no legacy row is
  materialized first). Prefer running it as part of `sharedModelContainer`
  construction or the earliest app lifecycle hook.

**Side effects (intended):** deleting CycleRecords nullifies
`PositivityToken.consumedByCycleRecord`, returning consumed PTs to the journal as
free tokens. Commitments are untouched (only CycleRecords deleted). Per-commitment
"Past Cycles" history resets to empty.

**Create:** `WilgoTests/CycleRecord/LegacyCycleRecordWipeTests.swift`

- With the flag unset, a container seeded with CycleRecords ends up with zero
  CycleRecords after the wipe runs, and the flag is set.
- With the flag already set, seeded CycleRecords are **preserved** (wipe is a
  no-op) — proves it doesn't nuke future records.
- A consumed `PositivityToken` becomes free (`consumedByCycleRecord == nil`)
  after its CycleRecord is wiped.
- (Factor the wipe into a testable function taking a `ModelContext` +
  `UserDefaults` so it runs against an in-memory container with an isolated
  `UserDefaults(suiteName:)`.)

**Manual verification (critical):** On a device/simulator that already has legacy
CycleRecords (letGo/other): launch the new build. App must **not crash**; the
FCR/Past Cycles history is empty; commitments still present; the wins journal
shows any previously-consumed PTs back as free.

**Dependencies:** Commit 1. Blocks nothing structurally, but should land before
on-device testing of later commits (otherwise legacy rows may crash the app).

---

### Phase 2 — FCR card UI on the shared-sheet architecture

Goal: the visible label pills, conditional reflection/PT UI, "?" popover, and the
**shared mint sheet shell** — built directly, no throwaway inline box. 3Sauce can
verify the label flow on-device here; the draft *behavior* lands in Commit 3.

#### Commit 2 — ui: card labels + conditional PT/reflection + "?" popover + shared mint sheet shell

**Modify:** `Wilgo/.../FCRCycleCardView.swift`

- `selectableOutcomes` → `[.intended, .excused, .moveOn, .punished]`
  (lightest→heaviest order).
- `CycleOutcome` display extension: add `.intended` ("Intended", tint TBD),
  rename `.letGo`→`.moveOn` ("Move on"), remove `.other`.
- Reflection header: drive REQUIRED/OPTIONAL off `state.isReflectionRequired`
  (now true only for Move on).
- `ptRow`: only render when `state.outcome?.requiresPT == true`. For
  Intended/Excused the row is hidden and the card closes on the label
  (+ optional note) alone.
- **Remove** the inline mint UI entirely: delete `@State mintText`,
  `@State isMinting`, and the inline `mintSheet` (they exist today). The
  "+ Mint one now" / "Needed" button now calls an `onRequestMint?()` closure —
  it does **not** expand an inline box.
- Add "?" button next to the "HOW ARE YOU CLOSING THIS?" header opening one
  `.popover` listing all four labels with the one-line copy above.

**Modify:** `Wilgo/.../FinishedCycleReportView.swift` — add the shared mint sheet
**shell** (behavior comes in Commit 3):

- `@State private var mintTarget: String?` — the `CycleReport.id` the mint sheet
  targets; non-nil ⇒ sheet presented. The card's `onRequestMint` sets it to that
  card's id.
- Present **one** `.sheet` with the mint UI (title "✨ One good thing", a
  TextField, "Save & use as PT"). In this commit the draft binding can be a
  simple local `@State` so the sheet is functional for verification; Commit 3
  replaces it with the single shared `pendingDraft` + carry-over/consume rules.

**Modify:** `Wilgo/.../FCRCycleCardState.swift` — `isReflectionRequired` becomes
`!isPassed && (outcome?.requiresReflection ?? false)`; `isComplete` rewritten to
the matrix. (Folded here so the UI is independently verifiable.)

**Create/Update:** `WilgoTests/FinishedCycleReport/FCRCycleCardStateTests.swift`
Update existing `.other`/`.letGo` references; add matrix completeness tests:

- `.intended` / `.excused` → `isComplete == true` with no PT, no reflection.
- `.moveOn` → incomplete without reflection; incomplete without PT; complete
  with both.
- `.punished` → incomplete without PT; complete with PT, reflection empty.
- Flip-to-passed still clears failure fields.

**Manual verification (critical):** Launch on iPhone 17 (UDID
`4492FF84-2E83-4350-8008-B87DE7AE2588`). Trigger an FCR with a failed cycle.
Verify: all four pills show; Intended/Excused close with no PT/no note; Move on
requires a note + PT; Punished requires a PT only; the "+ Mint one now" button
opens the shared sheet (not an inline box); "?" popover shows all four
explanations.

**Dependencies:** Commit 1.

---

### Phase 3 — Mint draft behavior (single shared draft)

Goal: make the shared mint sheet's draft a **single pending value** that carries
across cards and is consumed on save. This is the direct home for 3Sauce's
draft-handling decisions.

#### Commit 3 — feat: single shared mint draft — carry-over across cards, preserved on label switch, consumed on save

**Modify:** `Wilgo/.../FinishedCycleReportView.swift`

- Replace the sheet's local draft binding (from Commit 2's shell) with a
  parent-owned single draft:
  - `@State private var pendingDraft: String = ""` — the one in-progress mint
    text, shared by every card's sheet, bound to the TextField as `$pendingDraft`.
- **Preserve on non-save dismiss:** Cancel / swipe-down / opening the sheet from
  another card does **not** clear `pendingDraft`. Hiding a card's PT row on a
  label switch also cannot lose it — the draft lives on the parent, not the card.
- **Consume on save:** on "Save & use as PT", `mintAndAssign(reason:
  pendingDraft, to: mintTarget!)`, then set `pendingDraft = ""`. Once saved, the
  carry-over is gone.
- Also clear the carry-over when the user blanks the field themselves.

**Mint draft model (single source of truth):**

- There is **at most one** `pendingDraft`. Opening the sheet from any card shows
  it; editing it anywhere edits the one value.
- Therefore: type `aaa` on card A → open card B (shows `aaa`) → edit to `bbb` →
  back to A shows **`bbb`** — there is no separate per-card "aaa"; it was the
  same draft, overwritten. This is the only self-consistent behavior for a single
  shared draft, and is the decided behavior.
- Only **unsaved** drafts carry across cards. A **saved** PT never prefills
  anything (keeps the FCR-redesign journal-integrity decision intact — see
  [[project-fcr-redesign]] Refinement B).

**Create/Update:** factor the draft lifecycle into a tiny pure helper if it
reduces to logic (e.g. a `MintDraft` struct with `carryOver` / `consumeOnSave`
semantics) so it is unit-testable rather than pure SwiftUI @State:

- Typing then dismissing without save preserves the draft.
- Editing from a second target reflects the latest text everywhere (bbb).
- Save clears the draft; a subsequent open shows empty.
- A saved PT's text never becomes the next draft.

**Manual verification (critical):**
- Type a draft on card A, switch A's label to Intended, switch back to Move on:
  draft still present (in-memory preserve).
- Type `aaa` on A, open B (shows `aaa`), edit to `bbb`, reopen A: shows `bbb`.
- Save the draft as a PT on one card: reopening the sheet on another card shows
  an **empty** field (consumed on save).

**Dependencies:** Commit 2 (owns the shared-sheet shell + card `onRequestMint`).

---

### Phase 4 — PT assignment & release gating

Goal: PT auto-assignment, release, and record builder honor the matrix, matching
the UI and the shared-draft mint flow.

#### Commit 4 — logic: assign/consume/release PT by outcome, and re-reconcile on label change

The matrix means a card's PT-need can now **toggle mid-edit** as the user
switches labels (Move on/Punished ⇄ Intended/Excused). Assignment must react to
label changes, not just check-in/cycle-list changes — and a *minted* PT that
gets detached must be **kept in the wins journal**, never discarded (per
3Sauce's decision) or silently saved to the wrong place.

**Modify:** `Wilgo/.../FCRPTAssignment.swift` — `autoAssign` only considers
failed cycles that both are failed **and** whose selected outcome `requiresPT`.
The caller filters `failedCycleIDs` down to PT-requiring cycles (call it
`ptRequiringCycleIDs`) before passing them in.

**Modify:** `Wilgo/.../CycleRecordBuilder.swift` — only attach `consumedPT` when
`state.outcome?.requiresPT == true`; Intended/Excused records carry no PT.

**Modify:** `Wilgo/.../FinishedCycleReportView.swift` — the behavioral core:

- Add an `.onChange` watching an **outcome signature**
  (`allCycles.map { cardStates[$0.cycle.id]?.outcome }`) that calls
  `reconcilePTAssignments()`. Today reconciliation only fires on check-in count
  / cycle-list changes ([lines 82-88](../Wilgo/Features/Commitments/FinishedCycleReport/FinishedCycleReportView.swift#L82-L88));
  label edits bypass it entirely — the bug source.
- **Broaden the release rule** at
  [line 136](../Wilgo/Features/Commitments/FinishedCycleReport/FinishedCycleReportView.swift#L136):
  release a cycle's PT assignment when the cycle no longer requires a PT —
  i.e. it flipped passed **or** its label no longer `requiresPT`. Use
  `ptRequiringCycleIDs` instead of `failedCycleIDs` as the "still needs it" set.
- **Released tokens are kept, not deleted.** Releasing only clears
  `assignedPTs[cycleID]`; it does **not** delete the `PositivityToken`.
  - An auto-assigned free token simply returns to `freeTokens` (it was never
    consumed).
  - A **minted** token stays inserted in the context and unconsumed, so it
    persists as a free wins-journal entry and becomes available for a future
    failed card. (No rollback of the `modelContext.insert` from `mintAndAssign`.)
- Because a just-released minted token is now "free," `autoAssign` may re-pick it
  when a card re-acquires a PT need (Intended → Move on) — no token is stranded.

> Note on persistence of unconsumed minted tokens: `persistRecords` saves the
> context, so an inserted-but-unconsumed minted token is written as a standalone
> free PT. That is the intended outcome (the user's typed win is kept). Confirm
> during execution that a minted-then-detached token shows up in the wins
> journal as a normal free token.

**Create/Update:** `WilgoTests/FinishedCycleReport/FCRPTAssignmentTests.swift`,
`CycleRecordBuilderTests.swift`, `FCRCompletionTests.swift`

- No PT assigned to Intended/Excused cycles even when free tokens exist.
- PT assigned to Move on / Punished cycles oldest-first (existing behavior).
- Builder: Intended/Excused record has `consumedByCycleRecord == nil`.
- `FCRCompletion.canClose` across mixed states (one of each label).
- **Label-transition assignment (unit-level on `FCRPTAssignment` + view logic):**
  - Move on → Intended releases the auto-assigned free token back to the pool
    (token not consumed, available to another cycle).
  - Intended → Move on acquires a free token if one exists.
  - A token freed by one card is re-assignable to another PT-requiring card.

**Manual verification (critical, covers the minted-PT edge):** In an FCR with a
failed cycle: pick **Punished/Move on**, tap **Mint one now**, type a win, then
switch the label to **Intended**. Confirm: (1) the card closes with no PT, and
(2) the minted win is **still present in the wins journal** afterward (not
discarded, not double-counted). Also verify switching back to Move on re-attaches
a PT (the same freed one if it's the only free token).

**Dependencies:** Commit 1, **Commit 3** (release logic + auto-assign interact
with the shared-sheet mint flow and the parent-owned draft; land 3 first so the
mint path is the shared sheet + single draft, and released/minted tokens follow
the carry-over semantics).

---

### Phase 5 — Cleanup of lingering references

#### Commit 5 — chore: update remaining Let go/Other references (past cycles display, tests)

**OUTCOME: no-op — absorbed by Commit 1.** During execution, Commit 1's
implementer did a broad mechanical sweep of all `.letGo`/`.other` case usages and
display strings across the app and tests. Verification confirmed:
- `PastCyclesFormatting.swift` / `CommitmentDetailView.swift` use
  `record.outcome?.displayName` and `.passed` generically — they pick up the new
  labels via the shared `displayName` extension with no code change needed.
- The only remaining `letGo`/`other` string references are the **intentional**
  legacy-decode mapping in `CycleRecord.swift` (`case "letGo", "other"`) and its
  tests in `CycleOutcomeMatrixTests.swift`.
- No `.letGo`/`.other` case usages remain anywhere; no "Let go"/"Other" UI
  strings remain.

Nothing to commit for Commit 5.

**Dependencies:** Commit 1.

---

## Critical Files

| File                                                    | Role                                          |
| ------------------------------------------------------- | --------------------------------------------- |
| `Shared/Models/CycleRecord.swift`                       | `CycleOutcome` enum, matrix, legacy decode    |
| `Wilgo/.../FinishedCycleReport/FCRCycleCardState.swift` | Per-card completeness gating                  |
| `Wilgo/.../FinishedCycleReport/FCRCycleCardView.swift`  | Pills, conditional PT/reflection, "?" popover; opens shared mint sheet |
| `Wilgo/.../FinishedCycleReport/FinishedCycleReportView.swift` | Shared mint sheet + single draft; PT reconcile/release on label change |
| `Wilgo/.../FinishedCycleReport/FCRPTAssignment.swift`   | PT auto-assignment (matrix-aware)             |
| `Wilgo/.../FinishedCycleReport/CycleRecordBuilder.swift`| Persists consumed PT conditionally            |

### Dependency Graph

```
Commit 1: model — enum + matrix + decoder
    |
    +-- Commit 1b: migration — guarded one-time wipe of legacy CycleRecords   [after 1]
    +-- Commit 2:  ui — labels/PT/reflection/popover + shared mint sheet SHELL [after 1]
    |       |
    |       +-- Commit 3: feat — single shared mint draft (carry-over/consume) [after 2]
    |               |
    |               +-- Commit 4: logic — PT assign/release/reconcile by matrix [after 3]
    +-- Commit 5:  chore — remaining Let go/Other references                    [after 1]
```

Commit 1b and Commit 5 are independent after Commit 1 (1b should land before
on-device testing so legacy rows don't crash the app). Commit 2 → 3 → 4 is a
chain:
Commit 2 builds the card UI directly on a shared mint-sheet **shell** (no
throwaway inline box); Commit 3 makes the sheet's draft a single shared
carry-over value; Commit 4's release/reconcile logic drives that shared sheet
and keeps released/minted tokens.

---

## Edit-time PT transition behavior (important)

Because the matrix lets a card's PT-need toggle as the user re-labels, the FCR
must reconcile PT assignments on **label change**, not only on check-in/backfill
change. Rules:

- **No-PT → PT-needed** (e.g. Intended → Move on): auto-assign a free token if
  available; else the card shows "Needed" and the user mints one.
- **PT-needed → No-PT** (e.g. Move on → Intended): **release** the assignment.
  The token is **kept**, never deleted:
  - auto-assigned free token → returns to the free pool;
  - **minted** token → stays as a free, unconsumed wins-journal entry (the user
    typed a real win; we never discard their words).
- A released token is re-assignable to another PT-requiring card, and re-pickable
  if the same card swings back to a PT-needing label.

See Commit 4 for the implementation and tests.

### Mint draft (typed-but-unsaved) handling

The mint UI is **one shared sheet** across all cards, with a **single pending
draft** owned by the FCR view (not per-card local state). Rules:

- The draft is **preserved in-memory** for the life of the FCR — switching a
  card's label to a no-PT one (which hides its PT row) does **not** lose the
  typed text.
- The draft is **shared**: opening the sheet from any card shows the one pending
  draft; editing it anywhere edits that one value. (A→B edit→A shows the latest
  edit, not a stale per-card copy.)
- Only **unsaved** drafts carry across cards. A **saved** PT never prefills
  another card's sheet.
- The draft is **cleared on Save** (it became a real PT) or when the user blanks
  it.

The shared-sheet **shell** is built in Commit 2; the single-draft carry-over /
consume-on-save behavior is Commit 3.

---

## Open items

- Pick tint for `.intended` (TBD).
- Finalize exact "?" popover copy (draft above).
- Confirm the Commit 2/3 split of the `FCRCycleCardState` edit during execution.
- Confirm during execution that a minted-then-detached PT surfaces in the wins
  journal as a normal free token (persistence check).
