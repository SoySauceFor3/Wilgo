# Edit Commitment Feature (March 2026)

## Background

We added the ability to edit an existing commitment. Because Wilgo tracks skip-credit accounting
against historical check-in data, editing a commitment's configuration can have non-obvious
side effects on past and current credit calculations. This document records what we decided
and why.

---

## Field-by-field edit semantics

| Field                      | Effect on save                                                 |
| -------------------------- | -------------------------------------------------------------- |
| `title`                    | Immediate. No effect on credit accounting.                     |
| Slot time windows          | Immediate. Affects which windows are shown in Stage today.     |
| `timesPerDay` (slot count) | **Resets the period anchor to today** — see rule fields below. |
| `skipCreditCount`          | **Resets the period anchor to today** — see rule fields below. |
| `skipCreditPeriod`         | **Resets the period anchor to today** — see rule fields below. |
| `punishment`               | Immediate. Purely informational.                               |
| `proofOfWorkType`          | Immediate. No effect on credit accounting.                     |

The three fields `timesPerDay`, `skipCreditCount`, and `skipCreditPeriod` are collectively
called **rule fields**. Any change to any of them resets the period anchor to today. The
edit form shows a neutral info note when a rule field has changed: _"Changing rules starts
a fresh period from today."_

#### Why all three rule fields reset the period

Changing any rule field signals a new commitment. Making the app punish users for that
commitment is counter-productive:

- **Increasing `timesPerDay`**: the user wants to do more. If the app immediately burns
  credits for past days that didn't meet the new standard, that's demoralizing and will
  discourage ambitious goals.
- **Decreasing `skipCreditCount`**: the user wants to be stricter. If past misses now
  exceed the new limit and trigger immediate punishment, the app penalizes the user for
  deciding to hold themselves to a higher standard.
- **Changing `skipCreditPeriod`**: the accounting window itself changes, which can
  retroactively pull in weeks or months of history.

In all three cases: **new rules, new start**. The period anchor resets to today and the
user begins the new commitment with a clean slate.

---

## Period anchor: "today as the start of the new period"

### What it means

Every commitment has a `periodAnchor: Date` that determines when each credit period begins:

- **Weekly**: the period resets on the same weekday as `periodAnchor`, every week.
  Example: anchor = Friday → period runs Friday–Thursday, forever.
- **Monthly**: the period resets on the same day-of-month as `periodAnchor`, every month,
  clamped to the last day of shorter months.
  Example: anchor = March 31 → resets on the 31st (or last day) of each month.
- **Daily**: unaffected — always resets at midnight.

For **new commitments**, `periodAnchor` is set to `createdAt`. The commitment's first period begins
the day it was created.

When a user **edits `skipCreditPeriod`**, `periodAnchor` is updated to `Date.now`. This
means the new period type starts counting from today, with no retroactive history.

### Why not calendar boundaries (week start / 1st of month)?

Calendar-aligned periods feel arbitrary to users: "Why does my commitment reset on Monday when
I started it on Friday?" The anchor-based approach means "the period resets when _I_
decided to start it," which is more intuitive and personal.

### Why not ask the user to choose?

We considered a dialog on create/edit: "Start period on [today] or [natural calendar
boundary]?" We decided against it because:

1. The right answer is almost always "today." When you set up a commitment, you're committing
   starting now — you naturally want the accounting to reflect that.
2. Monthly commitments are especially confusing to ask about: "Should this reset on the 5th or
   the 1st?" Most users have no strong opinion and will pick the default anyway.
3. The dialog adds cognitive friction on every create/edit for a decision the user has
   already implicitly made by acting today.

### Why not a "pending change" that defers to the next natural boundary?

We briefly considered deferring a `skipCreditPeriod` change to the start of the _next_
natural period (e.g., next Monday if changing weekly). This avoids any "orphaned fragment"
period. However:

1. It requires storing both the old and new period types simultaneously, adding state
   machine complexity to `SkipCreditService`.
2. The "orphaned fragment" with the immediate approach is benign: the shortest possible
   transitional period is one day (e.g., changing to monthly on January 31st gives a
   one-day period before February 1st takes over via the natural monthly anchor logic).

---

### No `CommitmentConfigSnapshot` (history versioning)

We decided **not** to store a timestamped history of commitment configuration changes.

This was discussed in the context of a future history visualization (heatmap or ring
diagram). For a heatmap showing raw check-in counts per day, no goal/config history is
needed — `CheckIn.psychDay` is sufficient. For ring diagrams (progress toward a
period goal), a `CommitmentConfigSnapshot` model would be needed.

We deferred this because:

- The heatmap is the planned v1 visualization, requiring no config history.
- The shape of a ring diagram feature (daily rings vs. period rings) is unknown; building
  a snapshot model now risks building the wrong abstraction.
- When the time comes, a retroactive "initial snapshot" can be synthesized from
  `commitment.createdAt` + original config with a lightweight migration pass.

The architectural promise we do make: **never delete `CheckIn` records during an
edit.** Raw check-in data is the ground truth for all future history features.

---

### Notification ID stability

`MorningReportService` previously derived notification IDs from the commitment title slug.
Renaming a commitment orphaned the pending notification (the old ID could never be cancelled).

Fix: JSON-encode `commitment.persistentModelID` (SwiftData's built-in stable identifier,
backed by CoreData's URI-based object ID) as the notification ID base. No extra model
field is needed, and renames no longer affect pending notifications.

---

## Future Work

### Explicit period anchor control

There are two ways a user might want to control _when_ their period resets, beyond the
implicit "day of edit" default:

**Option A — "Ask user" dialog on create/edit**
Show a picker on the create/edit form: "Reset period starting from: [today] / [natural
calendar boundary]."

- Pro: explicit, discoverable.
- Con: cognitive friction on every create/edit; the right answer is almost always "today."

**Option B — Dedicated "Reset day" setting per commitment**
Add a secondary setting to the commitment detail: "Reset day" (weekday picker for weekly
commitments, day-of-month picker for monthly commitments). Only surfaced after the commitment is created,
as a power-user adjustment.

- Pro: no friction on the primary create flow; power users who want Monday resets can
  find it.
- Con: slightly hidden; two-step to configure.

**Our current lean:** Option B is more aligned with the principle of keeping the create
flow simple. If users consistently report wanting to change their reset day after creation,
add Option B. If they want to set it upfront, reconsider Option A.

Whichever option is chosen, the underlying mechanism (`periodAnchor: Date` on `Commitment`)
already supports it — it's purely a UI addition.
