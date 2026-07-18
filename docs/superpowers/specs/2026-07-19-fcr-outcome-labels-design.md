# FCR Outcome Labels & Per-Outcome Requirements — Design

**Date:** 2026-07-19
**Author:** 3Sauce (design), Claude (facilitation)
**Status:** Design — awaiting review
**Related workstream:** FCR Redesign (`#FCRRedesign`, branch `RedoFCR`) — see memory `project-fcr-redesign`
**PRD:** _(to be linked — Notion, provided by 3Sauce)_
**Tracking:** _(to be linked — Notion, provided by 3Sauce)_
**Tag (proposed):** `#FCROutcomeLabels`

---

## Problem

The Finished Cycle Report (FCR) currently gates every failed cycle behind a
uniform requirement: pick a label + assign exactly one Positivity Token (PT),
plus a written reflection *only* when the label is `.other`
([FCRCycleCardState.swift:50](../../../Wilgo/Features/Commitments/FinishedCycleReport/FCRCycleCardState.swift#L50)).

Two pain points:

1. **No "planned fail" label.** All existing labels are reactive
   (excused / punished / let go). Test commitments and intentional throwaway
   cycles have no honest home and get mislabeled.
2. **A PT is required for *every* failed cycle.** Writing a wins-journal entry
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
- No change to PT auto-assignment mechanics ([FCRPTAssignment.swift](../../../Wilgo/Features/Commitments/FinishedCycleReport/FCRPTAssignment.swift))
  beyond *which* cycles require a PT.
- No global user-facing config toggle. (Considered and rejected — see
  Alternatives.)

---

## The core design: an accountability model

Every failed cycle needs **exactly one form of accountability**, matched to the
label the user picks. This principle drives the whole requirement matrix:

- If the commitment has a **penalty** the user paid → **Punished** → the
  *payment* is the accountability → reflection optional.
- If the commitment has **no penalty** → **Move on** → the *reflection* is the
  accountability (its substitute for a penalty) → reflection required.
- **Intended** / **Excused** → the user asserts no accountability is warranted
  (planned, or justified) → nothing required.

### Outcome labels (final set — 4 labels, `.other` removed)

| Label        | Meaning                                                        |
| ------------ | ------------------------------------------------------------- |
| **Intended** | Planned / test / throwaway fail. Zero sting.                  |
| **Excused**  | A legitimate reason justified the miss (sick, emergency).     |
| **Move on**  | No plan, no reason, no penalty — acknowledge and continue.    |
| **Punished** | The user imposed a consequence (real-life, penalty or not).   |

`.other` is removed. `Move on` (renamed from the old `.letGo` "Let go") is the
honest catch-all: "none of the above."

### Requirement matrix

| Label        | Reflection   | PT required | Accountability source        |
| ------------ | ------------ | ----------- | ---------------------------- |
| **Intended** | Optional     | ❌ No        | none warranted (planned)     |
| **Excused**  | Optional     | ❌ No        | none warranted (justified)   |
| **Move on**  | **Required** | ✅ Yes       | the reflection               |
| **Punished** | Optional     | ✅ Yes       | the penalty already paid     |

Notes:
- The reflection field is **always present** under every label (an optional
  free-text note), matching current behavior. It is only *required* for
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

`CycleOutcome` (in [Shared/Models/CycleRecord.swift](../../../Shared/Models/CycleRecord.swift#L4)):

- **Add** `case intended`.
- **Rename** `case letGo` → `case moveOn`.
- **Remove** `case other`.

`CycleOutcome` is `String`-backed and `Codable`, persisted on `CycleRecord`.
This is a **persisted enum change** requiring migration handling:

- Existing records with `outcome == "letGo"` → map to `.moveOn`.
- Existing records with `outcome == "other"` → map to `.moveOn` (the new
  catch-all). Their existing `reflectionText` is preserved.

Migration approach to be finalized in the implementation plan (candidates:
custom decoding that maps legacy raw values, or a lightweight data migration
pass). The safe default: decode-time mapping of legacy raw strings so no data
rewrite is strictly required.

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
([FCRCycleCardState.swift:50-62](../../../Wilgo/Features/Commitments/FinishedCycleReport/FCRCycleCardState.swift#L50-L62))
are rewritten to consult these, replacing the hardcoded `.other` special-case
and the unconditional `hasAssignedPT` requirement.

---

## UI changes

In [FCRCycleCardView.swift](../../../Wilgo/Features/Commitments/FinishedCycleReport/FCRCycleCardView.swift):

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
requirement to *meaning* instead.

**Keep "Let go" as-is + add Intended + keep Other.**
Rejected: three labels (Intended / Excused / Let go / Other) would all blur into
"this is fine, close it." Renaming Let go → Move on and dropping Other yields a
clean, exhaustive partition.

**Remove Other with no free-text on fails.**
Rejected: would lose the ability to write a reflection on a failed cycle. Kept
the always-optional note under every label instead.

**Gate "Punished" on the `punishment` field being set.**
Rejected: `punishment` is only a pre-written reminder; users can improvise
real-life consequences. Hiding the label would have the app presume facts it
can't know.

---

## Open items for implementation plan

- Finalize migration approach for legacy `letGo` / `other` raw values.
- Confirm `#tag` and tracking link with 3Sauce.
- Exact help-popover copy and presentation (SwiftUI `.popover` vs inline).
