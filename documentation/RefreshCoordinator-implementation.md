# RefreshCoordinator — Implementation Plan

**PRD:** [Notifications, LA and widget refresh timings clean up](https://app.notion.com/p/Notifications-LA-and-widget-refresh-timings-clean-up-39d4b58e32c38097a527fd74a1626ce2?source=copy_link)
**Tracking:** [Notifications, LA and widget refresh timings clean up](https://app.notion.com/p/Notifications-LA-and-widget-refresh-timings-clean-up-39d4b58e32c38097a527fd74a1626ce2?source=copy_link)
**Tag:** #refreshCoordinator

---

## Context

`CommitmentChangeRefresher.refreshAll()` is the single choke point that rebuilds every user-facing surface (catch-up notifications, slot-start notifications, cycle-end notifications, the Now Live Activity, and the widget timeline). Today it is *triggered* by two ad-hoc mechanisms:

1. **Manual calls after a DB write.** Views and Intents each remember to call `refreshAll()` after `save()`. This is sprinkled across ~7 sites and is a DRY hazard — at least one save site (`FinishedCycleReportView`) already *forgets* to refresh, and any future save site can silently do the same.

2. **A fixed hourly timer.** `CatchUpReminder.startHourlyRunWhileActive()` runs an `InAppScheduler(interval: 1h)` that calls `CatchUpReminder.refresh()` (only CatchUp — not the full `refreshAll()`). This exists because *time passing* changes reality without any DB write: a slot opens/closes, a cycle rolls over, and a commitment silently becomes "behind." The hourly cadence is both too coarse (fires ~24×/day when nothing crossed) and off-boundary (a slot that starts at 2:05 isn't reflected until 3:00).

This workstream unifies both triggers behind one owner so that `refreshAll()` runs **whenever reality changes** — either a meaningful DB write, or the crossing of a scheduled time boundary — with no per-call-site discipline.

The work layers on top of the completed `#notification #DRY` workstream (the `BackgroundRefreshScheduler` template and `refreshAll()` aggregator). It is a new *trigger* capability, not a change to the refresh *plumbing*.

---

## Architecture Summary

Introduce **`RefreshCoordinator`** — a `@MainActor` class started once from `WilgoApp.init`, living at `Wilgo/Features/LiveUpdates/RefreshCoordinator.swift` (alongside `CommitmentChangeRefresher`, which it drives), owning all *automatic* `refreshAll()` triggers. It answers one question in one place: "when should `refreshAll()` fire without anyone explicitly asking?" It has two independent trigger sources:

### Trigger A — DB change (always-on `didSave` observer)

`RefreshCoordinator` observes `ModelContext.didSave` notifications for the app's canonical context (`ModelContext.wilgoMain`). On any save it fires a fire-and-forget `Task { await CommitmentChangeRefresher.refreshAll() }`.

Because Intents run **in the app process and save through `wilgoMain`** (see `CheckInIntent.perform()` / `SnoozeIntent`), the observer sees Intent saves too — the observer is genuinely "always on," not foreground-only.

This lets us **delete the manual `refreshAll()` call from the 5 view sites** and **automatically cover the currently-missing `FinishedCycleReport` save**. Intents, however, **keep** their explicit awaited `refreshAll()` — see Design Decisions.

No debounce in v1 (see Design Decisions). `refreshAll()` is idempotent, so extra fires are wasted work, never incorrectness.

### Trigger B — time boundary (self-rescheduling boundary timer)

`RefreshCoordinator` computes the next meaningful time boundary via the *existing* `StageCharacterization.nextStageRefreshTime(commitments:now:)` — the earlier of the next slot-window edge and the next cycle/midnight boundary. This is the *same* policy `NowLiveActivityManager` already uses for its background wake (`nextWakeEarliestDate`).

It schedules a **one-shot** timer to fire *at* that instant. On fire: `await refreshAll()`, then recompute the next boundary and reschedule. This replaces `CatchUpReminder.startHourlyRunWhileActive()` and its `InAppScheduler` usage entirely — firing precisely *at* boundaries instead of hourly.

### What is deliberately untouched

- **BGTask background wakes** (`BackgroundRefreshScheduler.refresh()` machinery) — unchanged.
- **The scene-phase `refreshAll()` in `WilgoApp`** — remains the watchdog for BG wakes iOS skipped, and the last refresh before suspension. `RefreshCoordinator`'s in-app timer complements it (fine-grained, while active); scene-phase covers activation/backgrounding.
- **`CommitmentChangeRefresher.refreshAll()` itself** — unchanged; still the single choke point.
- **Intent `refreshAll()` calls** — kept (process-lifetime requirement).

---

## Design Decisions

### One owner type for both triggers

**Decision:** A single `RefreshCoordinator` owns both the `didSave` observer and the boundary timer.

**Why not two separate types?** Both mechanisms answer the *same* question — "when should `refreshAll()` fire automatically?" — from two signals (a DB write, a clock boundary). One type means one place a future reader looks to understand *all* automatic-refresh triggers, and one lifecycle to start from `WilgoApp`. The two mechanisms share no tricky state, so splitting them would buy no isolation while fragmenting the story.

### Intents keep their explicit awaited `refreshAll()`; the observer replaces only the view calls

**Decision:** The `didSave` observer replaces the fire-and-forget `refreshAll()` in the **5 view sites** (`AddCommitmentView`, `EditCommitmentView`, `ListCommitmentView`, `ArchivedCommitmentsView`, `FinishedCycleReportView`). **Intents** (`CheckInIntent`, `SnoozeIntent`) **keep** their explicit `await CommitmentChangeRefresher.refreshAll()`.

**Why not route Intents through the observer too?** An Intent's `perform()` keeps the app process alive **only until it returns**. The refresh *must* be awaited inside `perform()` or iOS tears the process down mid-refresh. The observer reacts via a detached `Task`, which `perform()` has no clean way to await without inventing a rendezvous mechanism (a continuation the observer signals) — real complexity added solely to remove two already-correct, already-explicit lines. View saves have no such lifetime constraint (the foreground process isn't going anywhere), so fire-and-forget via the observer is safe there.

**Risk: double-refresh on Intent saves.** With no debounce, an Intent save triggers **two** `refreshAll()` runs — the awaited explicit one, plus the observer's fire-and-forget one. **Mitigation:** both are idempotent, so this is correct-but-wasteful, not buggy. It is exactly the kind of redundancy the deferred debounce (below) would collapse. Accepted for v1.

### No debounce in v1 (noted for later)

**Decision:** The observer fires one `refreshAll()` per `didSave`, with no coalescing.

**Why not debounce now?** Keeps v1 minimal and the commit history clean (one concern per commit). `refreshAll()` is idempotent, so the only cost of a save-burst (e.g. an insert-commitment flow that saves several times, or the Intent double-refresh above) is redundant work, never wrong output.

**Risk: performance under save-bursts.** **Mitigation:** if profiling shows redundant `refreshAll()` runs are a real cost, add a short-window debounce (e.g. coalesce saves within ~300ms into one refresh) as a follow-up. This is explicitly deferred, not forgotten.

### Boundary timer reuses `nextStageRefreshTime`

**Decision:** Compute the next fire instant with `StageCharacterization.nextStageRefreshTime(commitments:now:)` rather than a new boundary calculation.

**Why not a fresh calculation?** That function already folds "next slot edge" and "next cycle/midnight boundary" into a single `Date`, is already unit-tested, and is already the wake policy `NowLiveActivityManager` uses for its BG task. Reusing it keeps the in-app timer and the background wake anchored to the *same* definition of "next boundary," so foreground and background stay consistent.

**Risk: the psychDay approximation.** `nextStageRefreshTime` approximates the true cycle end with "the next midnight," so the timer may fire once/day at midnight as a harmless no-op recompute. **Mitigation:** none needed — this is an intentional simplicity trade documented on the function itself; a no-op `refreshAll()` at midnight is cheap and idempotent.

### One-shot reschedule vs a repeating `Timer`

**Decision:** The boundary timer is a **one-shot** that reschedules itself after each fire (recomputing `nextStageRefreshTime`), rather than `InAppScheduler`'s repeating fixed-interval `Timer`.

**Why?** The next boundary is not a fixed interval — it depends on the current commitments and the current time. A repeating timer can't express "fire at the next edge, whatever it is." One-shot-then-recompute is the only shape that fires *at* boundaries.

---

## Major Model Changes

| Entity | Change |
| ------ | ------ |
| **New:** `Wilgo/Features/LiveUpdates/RefreshCoordinator.swift` | New `@MainActor` class owning the `didSave` observer + the self-rescheduling boundary timer; both drive `CommitmentChangeRefresher.refreshAll()`. |
| `Wilgo/WilgoApp.swift` | Start `RefreshCoordinator` from `init` (replacing the `CatchUpReminder.startHourlyRunWhileActive()` call). |
| `Wilgo/Features/LiveUpdates/Schedulers/CatchUpReminder.swift` | Delete `startHourlyRunWhileActive()`, the `scheduler` property, and the in-app-scheduler comment block. CatchUp keeps its `BackgroundRefreshScheduler` conformance and `performWork()`. |
| `Wilgo/Features/Commitments/Form/AddCommitmentView.swift` | Remove manual `Task { await refreshAll() }` after `save()`. |
| `Wilgo/Features/Commitments/Form/EditCommitmentView.swift` | Remove manual `Task { await refreshAll() }` after `save()`. |
| `Wilgo/Features/Commitments/ListCommitmentView.swift` | Remove manual `Task { await refreshAll() }` after `save()`. |
| `Wilgo/Features/Commitments/ArchivedCommitmentsView.swift` | Remove the 2 manual `Task { await refreshAll() }` calls after `save()`. |
| `Wilgo/Features/Commitments/FinishedCycleReport/FinishedCycleReportView.swift` | No code change — it saves but never called `refreshAll()` (the missing-refresh gap). The observer now covers it automatically. |
| `Shared/InAppScheduler.swift` | Becomes unused after CatchUp drops it. **Delete** if no other references remain (grep confirms CatchUp is the sole user). |

---

## Commit Plan

Every commit must leave the app building and add unit tests for the actual code change (per CLAUDE.md). Tests use the required iPhone 17 simulator via `./test-with-cleanup.sh`.

A note on testability: `RefreshCoordinator` should take its dependencies (the refresh action, and a "now"/boundary provider) as injectable seams so the observer and timer logic can be unit-tested without hitting the real `UNUserNotificationCenter`/`ActivityKit`. Mirror the existing seam style (`BGWakeTask`, injected `now:` params). Exact seam shape to be finalized in the writing-plans phase.

---

### Phase 1 — Boundary timer (Trigger B)

Goal: replace CatchUp's hourly `InAppScheduler` with a boundary-driven timer inside a new `RefreshCoordinator`. This is self-contained and independently verifiable.

#### Commit 1 — Add `RefreshCoordinator` with the self-rescheduling boundary timer

**Create:** `Wilgo/Features/LiveUpdates/RefreshCoordinator.swift`
- `@MainActor` class with a `start()` that schedules a one-shot timer at `StageCharacterization.nextStageRefreshTime(commitments:now:)`.
- On fire: `await CommitmentChangeRefresher.refreshAll()`, recompute next boundary, reschedule.
- Inject the boundary provider and the refresh action for testing.

**Create:** `WilgoTests/LiveUpdates/RefreshCoordinatorTimerTests.swift`
- Fires the refresh action at the computed boundary (via injected clock/provider).
- After firing, reschedules to the *next* boundary (not a fixed interval).
- Recomputes the boundary from current commitments each cycle (a new commitment shifts the next fire).

#### Commit 2 — Wire `RefreshCoordinator` into `WilgoApp`; remove CatchUp's hourly timer

**Modify:** `Wilgo/WilgoApp.swift` — replace `CatchUpReminder.startHourlyRunWhileActive()` with `RefreshCoordinator` start.
**Modify:** `Wilgo/Features/LiveUpdates/Schedulers/CatchUpReminder.swift` — delete `startHourlyRunWhileActive()`, the `scheduler` property, and the stale in-app-scheduler comment.
**Delete (if unused):** `Shared/InAppScheduler.swift` — confirm via grep that CatchUp was the sole user.

**Manual verification:** Launch on iPhone 17 sim. Confirm the app builds/runs and that surfaces still refresh when a slot boundary is crossed while foregrounded (watch Console subsystem `wilgo`). This depends on Commit 1.

---

### Phase 2 — DB-change observer (Trigger A)

Goal: add the always-on `didSave` observer and remove the view-site manual calls. Depends on Commit 1 (the `RefreshCoordinator` type existing).

#### Commit 3 — Add the `didSave` observer to `RefreshCoordinator`

**Modify:** `Wilgo/Features/LiveUpdates/RefreshCoordinator.swift` — observe `ModelContext.didSave` for `wilgoMain`; on save, fire-and-forget `Task { await refreshAll() }`. No debounce.

**Create/extend:** `WilgoTests/LiveUpdates/RefreshCoordinatorObserverTests.swift`
- A `save()` on the observed context triggers the refresh action.
- Multiple saves each trigger (documents the no-debounce v1 behavior).
- (If feasible with a seam) the observer is scoped to the intended context.

#### Commit 4 — Remove manual `refreshAll()` from the 5 view sites

**Modify:** `AddCommitmentView.swift`, `EditCommitmentView.swift`, `ListCommitmentView.swift`, `ArchivedCommitmentsView.swift` (×2) — delete the `Task { await refreshAll() }` after `save()`.
**No change (beneficiary):** `FinishedCycleReportView.swift` has a `save()` but *no* `refreshAll()` call today — it is the currently-missing-refresh gap. Nothing to remove; the observer now covers it automatically. This commit is what closes that gap.
**Keep untouched:** `CheckInIntent.swift`, `SnoozeIntent.swift` — their explicit awaited `refreshAll()` stays (process-lifetime).

**Manual verification:** Launch on iPhone 17 sim. Add/edit/archive a commitment and check in via widget/LA; confirm every surface refreshes exactly as before (Console subsystem `wilgo`). Confirm a finished-cycle save now refreshes (previously missed).

---

## Critical Files

| File | Role |
| ---- | ---- |
| `Wilgo/Features/LiveUpdates/RefreshCoordinator.swift` (new) | Owns both automatic triggers |
| `Wilgo/WilgoApp.swift` | Starts the coordinator; drops CatchUp hourly start |
| `Wilgo/Features/LiveUpdates/Schedulers/CatchUpReminder.swift` | Loses its in-app hourly timer |
| `Shared/Scheduling/StageCharacterization.swift` | Provides `nextStageRefreshTime` (reused, unchanged) |
| `Shared/InAppScheduler.swift` | Deleted once unused |

### Dependency Graph

```
Commit 1: RefreshCoordinator + boundary timer
    |
    +-- Commit 2: wire into WilgoApp, drop CatchUp hourly   [after 1]
    +-- Commit 3: add didSave observer                      [after 1, parallel to 2]
            |
            +-- Commit 4: remove view-site manual calls     [after 3]
```

Commits 2 and 3 are independent after Commit 1. Commit 4 depends on Commit 3.
