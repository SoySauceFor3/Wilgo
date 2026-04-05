# Cycle Anchor Change: Always Start on Monday / 1st of Month

## Context

Currently, `Cycle.anchored(kind, at: .now)` anchors cycles to **today's psych-day** on creation or rule edits. This means a weekly commitment created on Thursday has Thu–Wed cycles. The proposed change: always anchor weekly cycles to **Monday** and monthly cycles to the **1st of the month**. This is a trial — backward compatibility is required so it can be reverted.

---

## Core Design Principles

1. **Target always changes immediately.** When the user saves an edit, the new target is shown everywhere right away (Stage, progress bars, heatmap).
2. **Cycles are always displayed as complete.** No "~partial" visual — a weekly cycle is always shown as Mon–Sun regardless of when the commitment was created or edited.
3. **The only consequence of a grace period is in FinishedCycleReport:** grace cycles are excluded from penalty and PT evaluation. They still appear in the report normally.
4. **Grace at creation and on edit** are both the user's choice via a modal.

---

## Decisions

| Question                           | Decision                                                                                                    |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Daily cycles                       | Unchanged — anchor to today (trivially 1 day)                                                               |
| Stage view denominator             | Full target count always (e.g., 0/7)                                                                        |
| Partial/grace cycle in UI          | NOT shown — cycles always display as full date ranges, but grace cycles can show different UI so user knows |
| Grace cycle in FinishedCycleReport | Shown differently with UI cues; verdict row says "no penalty · grace period"                                |
| Rule-change modal scope            | All rule changes (target count AND cycle kind)                                                              |
| "Apply now" behavior               | New target shown everywhere immediately — always                                                            |
| Modal question                     | "Should the current cycle count toward penalties?"                                                          |
| Modal options                      | "Yes — I'm committed now" / "No — grace period for this cycle"                                              |

---

## The Grace Cycle Concept

A cycle is a **grace cycle** by user's choice.

Grace cycles:

- Display normally in FinishedCycleReport (full date range, actual check-ins, target) but maybe with UI cues showing it is grace cycle.
- No penalty triggered regardless of check-in count
- No PT tokens consumed
- A small note: "no penalty · grace period" in the verdict row

---

## UI/UX Details

### 1. Rule-Change Modal

Shown whenever any rule changes in EditCommitmentView (count or kind). Replaces the current direct-save flow.

```
┌──────────────────────────────────────────┐
│  Goal updated to 3 per month.            │
│                                          │
│  Should this month count toward          │
│  penalties?                              │
│                                          │
│  [Yes — I'm committed now]               │
│  [No — grace period for this month]      │
└──────────────────────────────────────────┘
```

- **"Yes — I'm committed now":** Save target immediately. `scheduledEffectiveDate = nil`. Current cycle evaluates normally.
- **"No — grace period":** Save target immediately (shown everywhere now). Set `scheduledEffectiveDate = end of current cycle`. Current cycle is grace in FinishedCycleReport.

**No modal if no rule changed** (e.g., only SlotWindows or punishment string changed).

---

## Other Features — No Change Needed

| Feature                                       | Impact                                                                  |
| --------------------------------------------- | ----------------------------------------------------------------------- |
| Heatmap (`Heatmap/Data.swift`)                | New commitments show clean Mon–Sun rows. Old unchanged. No code change. |
| PT monthly cap (`PositivityTokenCompensator`) | Grace cycles skipped entirely — cap unaffected.                         |
| `DayStartReport`                              | Uses cycle boundaries, not anchors. Unaffected.                         |
| Stage view denominator                        | Full count always. No change.                                           |

---

## Verification Plan

1. **New weekly commitment created Wednesday** → Stage shows Mon–Sun full cycle, denominator is full count; next Monday's FinishedCycleReport shows "no penalty · grace period" for that first cycle
2. **New monthly commitment created on 15th** → cycle is 1st–31st; first cycle is grace in report
3. **Edit count, pick "Yes — committed now"** → Stage immediately shows new count; current cycle evaluates with penalty
4. **Edit count, pick "No — grace period"** → Stage immediately shows new count; current cycle shows "no penalty · grace period" in report
5. **Edit CycleKind (weekly→monthly), pick grace** → new monthly cycle shown in Stage immediately; transition cycle is grace in report
6. **Edit with no rule change** → no modal shown, direct save
7. **Existing commitment (pre-change)** → cycle boundaries unchanged, no grace applied
