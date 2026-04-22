# UI Redesign — Information Architecture

**Date:** 2026-04-21  
**Status:** Draft — pending review  
**Design principles:** Clarity-first on main surfaces. Density acceptable in detail/history views. Progressive disclosure — detail is one tap away, not upfront.

---

## Stage / "Today" Tab

The most important screen. Daily driver. Must be ruthlessly focused.

### Grouping rationale

Commitments are grouped into three phases because the user's intent differs per group:


| Group        | User intent                               | IA principle                                                  |
| ------------ | ----------------------------------------- | ------------------------------------------------------------- |
| **Current**  | Act now — this is in my time window       | Maximize check-in button prominence, show time remaining      |
| **Catch Up** | I missed this — decide whether to recover | Show it's overdue, still allow check-in, communicate how late |
| **Upcoming** | Awareness only — nothing to do yet        | Minimal info, no action, just "starts at Xpm"                 |


Upcoming cards should be visually quieter (dimmed, no check-in button). Current cards are the loudest thing on screen.

---

### Current group

*In an active time slot right now.*

**Must have:**

- Commitment name
- Active slot time range (e.g. "1–5 PM") — no "Current Slot" label, it's obvious from context
- Check-in count / target for this cycle (e.g. "1/3 check-ins · Today")
- "Next Up: N slots" — remaining opportunities in the cycle
- "Behind +N" in red if behind on target
- Check-in button (primary, most prominent)
- Snooze button (secondary)

**Nice to have:**

- Encouragement message
- Last 14 days mini heatmap
- Tag — can help as a mental grouping cue, but title is usually sufficient
- Grace indicator — subtle badge/hint if current cycle is in grace (neutral tone: "this cycle is advisory only")

**Exclude:**

- Full history, stats — detail view territory
- Punishment — contradicts the encouraging tone

---

### Catch Up group

*No active slot right now, but behind on target for the current cycle. "Catch up" is about being below the cycle target count — not about missing a specific day.*

**Must have:**

- Commitment name
- Check-in count / target for this cycle (e.g. "1/3 check-ins · This week")
- "Slots left: N" — how many opportunities remain to recover (renamed from "Next up Slots")
- "Behind +N" in red
- Check-in button

**Nice to have:**

- Encouragement message — most valuable here, as the user is behind and a motivational nudge matters most
- Last 14 days mini heatmap
- Tag
- Grace indicator — subtle badge/hint if current cycle is in grace

**Exclude:**

- Snooze button — no active slot to snooze
- Any "overdue from X" language — behind-ness is per-cycle, not per-day
- Punishment

---

### Upcoming group

*Has a future slot today but it hasn't started yet. Nothing to act on.*

**Must have:**

- Commitment name
- Next slot start time (e.g. "starts at 8 PM")

**Nice to have:**

- "Behind +N" badge if already behind on cycle target (awareness only, softer color than Current/CatchUp)
- Tag

**Exclude:**

- Check-in button — nothing to do yet
- Snooze button
- Heavy visual weight — this group is the lowest priority on screen

---

## Commitment List Tab

Browse/manage mode, and fallback action surface for commitments not on Stage today. The check-in button is always available here regardless of whether the commitment appears on Stage.

**Must have:**

- Commitment name
- Tag(s)
- Target (e.g. "3× daily") or disabled
- Current cycle progress
- check-in button
(e.g. "2/3" on or near the button — collapses progress and action into one element)

**Nice to have:**

- Reminder windows (slot times) — config detail, useful occasionally
- Stage status indicator (Current / Catch Up / —) — lets user know if it's already prioritized on Stage
- Grace indicator — subtle hint if current cycle is in grace (neutral tone)
- Sort/filter controls (by tag — already exists)

**Exclude:**

- Proof-of-work badge — too niche for the list
- Punishment text — detail view territory
- Reminders enabled/disabled flag — already implied by Stage presence; bury to detail

---

## Commitment Detail View

User opted in to see more. Density is fine here. Three sections: header/config summary, current state, history. Edit entry point lives in toolbar.

---

### Section 1 — Config summary (read-only)

*Helps interpret the current state and history. Full config editing belongs in Edit view.*

**Must have:**

- Commitment name
- Cycle type (daily/weekly/monthly) — context for reading the heatmap
- Target count (e.g. "3×") — context for interpreting progress
- Enabled/disabled toggle — common enough action to live here, not buried in Edit

**Nice to have:**

- Tags — passive info, quick to scan
- Reminder windows (slot times) — answers "when is this supposed to happen?" without opening Edit
- Active grace period indicator — if current cycle is in grace, show it here (status, not config)

**Edit only (not shown here):**

- Encouragements, punishment, grace period config

---

### Section 2 — Current state

*How are you doing this cycle right now.*

**Must have:**

- Current cycle check-in count

**Nice to have:**

- Behind count if applicable

---

### Section 3 — History

*The main reason someone opens this view.*

**Must have:**

- Heatmap / check-in history
- Backfill check-in entry point

**Nice to have:**

- All-time check-in count
- Days tracked since creation — gives a sense of how established this commitment is

---

## Positivity Tokens Tab

**Must have**

- Mint button (disabled when capacity = 0)

**Exclude:**

- Token economy explanation — onboarding territory

### Section Summary

- {Active count} / {created}
- monthly budget remaining
- mint capacity = max(0, total check in count - created)

### Section PT reasons

- reason text

---

## Settings

**Must have:**

- Monthly PT cap (1–10 picker)
- Tags management (reorder, edit, delete)

**Nice to have:**

- Global reminders toggle

**Exclude:**

- Per-commitment settings — those live on the commitment itself

---

## Widget

Glanceable. Primary action: tap to open app or check in directly.

**Must have:**

- Commitment title
- Cycle progress (e.g. "1/3 · Today")
- Active slot time or "starts at X" for upcoming
- Stage indicator (current / catch up / upcoming)
- Check-in button (executes CheckInIntent directly)

**Nice to have:**

- Multiple commitments in medium/large widget
- Behind count badge

**Exclude:**

- Snooze in small widget — not enough space

---

## Live Activity

Most constrained surface. User is on lock screen.

**Must have:**

- Commitment name
- Active slot time range
- Check-in button (Done)
- Snooze button

**Nice to have:**

- Encouragement message
- Secondary commitments line (e.g. "+ 2 more active")

