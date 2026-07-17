# RefreshCoordinator — Implementation Plan

**PRD: NA**  
**Tracking:** [Notifications, LA and widget refresh timings clean up](https://app.notion.com/p/Notifications-LA-and-widget-refresh-timings-clean-up-39d4b58e32c38097a527fd74a1626ce2?source=copy_link)
**Tag:** #refreshCoordinator

---

## Context

`CommitmentChangeRefresher.refreshAll()` is the single choke point that rebuilds every user-facing surface (catch-up notifications, slot-start notifications, cycle-end notifications, the Now Live Activity, and the widget timeline). Today it is _triggered_ by two ad-hoc mechanisms:

1. **Manual calls after a DB write.** Views and Intents each remember to call `refreshAll()` after `save()`. This is sprinkled across ~7 sites and is a DRY hazard — at least one save site (`FinishedCycleReportView`) already _forgets_ to refresh, and any future save site can silently do the same.
2. **A fixed hourly timer.** `CatchUpReminder.startHourlyRunWhileActive()` runs an `InAppScheduler(interval: 1h)` that calls `CatchUpReminder.refresh()` (only CatchUp — not the full `refreshAll()`). This exists because _time passing_ changes reality without any DB write: a slot opens/closes, a cycle rolls over, and a commitment silently becomes "behind." The hourly cadence is both too coarse (fires ~24×/day when nothing crossed) and off-boundary (a slot that starts at 2:05 isn't reflected until 3:00).

This workstream unifies both triggers behind one owner so that `refreshAll()` runs **whenever reality changes** — either a meaningful DB write, or the crossing of a scheduled time boundary — with no per-call-site discipline.

The work layers on top of the completed `#notification #DRY` workstream (the `BackgroundRefreshScheduler` template and `refreshAll()` aggregator). It is a new _trigger_ capability, not a change to the refresh _plumbing_.

---

## Architecture Summary

Introduce `RefreshCoordinator` — a `@MainActor` class started once from `WilgoApp.init`, living at `Wilgo/Features/LiveUpdates/RefreshCoordinator.swift` (alongside `CommitmentChangeRefresher`, which it drives), owning all _automatic_ `refreshAll()` triggers. It answers one question in one place: "when should `refreshAll()` fire without anyone explicitly asking?" It has two independent trigger sources.

`RefreshCoordinator` is deliberately **thin wiring**: the two trigger mechanisms are each extracted into their own standalone unit, and the coordinator just constructs them, connects them, and owns the start/stop lifecycle:

- **`BoundaryTimer`** (`Wilgo/Features/LiveUpdates/BoundaryTimer.swift`) — owns the time-boundary mechanism: "fire a callback at the next boundary, then recompute and re-arm." Owns its `Timer` directly; the test seam is a single injected "arm" closure (no protocol — see Design Decisions). Knows nothing about SwiftData.
- **`ModelContextSaveObserver`** (`Wilgo/Features/LiveUpdates/ModelContextSaveObserver.swift`) — a **generic, Wilgo-agnostic** unit: "watch one `ModelContext` for `didSave` (object-scoped) and run a closure on each save." Knows nothing about timers or `refreshAll`.
- **`RefreshCoordinator`** — builds both units and wires them: the timer's `onFire` = refresh; the observer's `onSave` = fire-and-forget refresh **and** re-arm the boundary timer. Owns `start()`/`stop()` + the `didStart` idempotency guard.

This keeps each mechanism independently understandable and testable, and stops the `NotificationCenter`/`Timer` machinery from mingling in one confusing class. The two trigger sources:

### Trigger A — DB change (always-on `didSave` observer)

`RefreshCoordinator` observes `ModelContext.didSave` notifications for the app's canonical context (`ModelContext.wilgoMain`). On any save it does **two** things:

1. fires a fire-and-forget `Task { await CommitmentChangeRefresher.refreshAll() }`, and
2. **reschedules the boundary timer** (Trigger B), because a DB write can change what the next boundary _is_.

Point 2 is essential: `nextStageRefreshTime` is a pure function of the current commitment set, so a save that adds/edits/deletes a commitment or slot can move the next boundary earlier (a new 14:30 slot when the timer was set for 18:00 → the edge would be missed) or invalidate it (deleting the commitment that owned the next edge → the timer is scheduled for an instant that no longer matters). The boundary timer's schedule is _derived state over the commitment set_; the observer is exactly the thing that detects that set changing, so it must invalidate-and-recompute the schedule. This reuses the timer's own recompute-and-reschedule step — one method, two callers (the timer's own fire, and the observer).

Because Intents run **in the app process and save through** `wilgoMain` (see `CheckInIntent.perform()` / `SnoozeIntent`), the observer sees Intent saves too — the observer is genuinely "always on," not foreground-only.

This lets us **delete the manual** `refreshAll()` **call from the 5 view sites** and **automatically cover the currently-missing** `FinishedCycleReport` **save**. Intents, however, **keep** their explicit awaited `refreshAll()` — see Design Decisions.

No debounce in v1 (see Design Decisions). `refreshAll()` is idempotent, so extra fires are wasted work, never incorrectness.

### Trigger B — time boundary (self-rescheduling boundary timer)

`RefreshCoordinator` computes the next meaningful time boundary via the _existing_ `StageCharacterization.nextStageRefreshTime(commitments:now:)` — the earlier of the next slot-window edge and the next cycle/midnight boundary. This is the _same_ policy `NowLiveActivityManager` already uses for its background wake (`nextWakeEarliestDate`).

It schedules a **one-shot** timer to fire _at_ that instant. On fire: `await refreshAll()`, then recompute the next boundary and reschedule. This replaces `CatchUpReminder.startHourlyRunWhileActive()` and its `InAppScheduler` usage entirely — firing precisely _at_ boundaries instead of hourly.

### What is deliberately untouched

- **BGTask background wakes** (`BackgroundRefreshScheduler.refresh()` machinery) — unchanged.
- **The scene-phase** `refreshAll()` **in** `WilgoApp` — remains the watchdog for BG wakes iOS skipped, and the last refresh before suspension. `RefreshCoordinator`'s in-app timer complements it (fine-grained, while active); scene-phase covers activation/backgrounding.
- `CommitmentChangeRefresher.refreshAll()` **itself** — unchanged; still the single choke point.
- **Intent** `refreshAll()` **calls** — kept (process-lifetime requirement).

---

## Design Decisions

### One owner, but each trigger mechanism extracted into its own unit

**Decision:** A single `RefreshCoordinator` is the one place that owns _policy_ ("when should `refreshAll()` fire automatically?") and lifecycle. But the two _mechanisms_ are each extracted into a standalone unit — `BoundaryTimer` (the clock trigger) and `ModelContextSaveObserver` (the DB-save trigger) — and the coordinator is thin wiring over them.

**Why one owner (not two unrelated top-level types)?** Both triggers answer the same question, from two signals (a DB write, a clock boundary). One owner means one place a future reader looks to understand _all_ automatic-refresh triggers, and one lifecycle to start from `WilgoApp`. The triggers are also coupled: a DB write must _also_ reschedule the boundary timer (see next decision), and that wiring lives in the owner.

**Why extract the mechanisms into units (not inline in the coordinator)?** Inlining put `NotificationCenter`/`didSave` machinery and `Timer` machinery in the same class, which read as an incoherent mix — a reviewer genuinely mistook the observer code for an unrelated bug fix. Splitting them makes each mechanism independently understandable and unit-testable, and keeps `RefreshCoordinator` small enough to hold in your head. `ModelContextSaveObserver` is intentionally **generic** (watch a context, run a closure) — all Wilgo-specific meaning ("refresh + reschedule") lives in the closure the coordinator supplies, so the observer is a dumb, reusable mechanism and the _policy_ stays in one place.

**Risk: over-splitting.** Three types for one feature could fragment the story. **Mitigation:** capped at exactly three (owner + two units); the coordinator staying thin/forwarding is the intended shape, not a smell.

### `BoundaryTimer`'s test seam is an injected closure, not a protocol

**Decision:** `BoundaryTimer` owns its `Timer` directly and exposes ONE injectable closure for the "arm a one-shot fire at this date" step — `arm: (Date, @escaping () async -> Void) -> Void`, defaulting to the real main-run-loop `Timer`. There is **no** `BoundaryScheduler` protocol and **no** `TimerBoundaryScheduler` class.

**Why not the protocol?** The protocol existed only as a test seam (swap the real `Timer` for a fake that fires on command). But it had exactly one production conformer and one test conformer — a protocol earns its keep with multiple real implementations or a complex contract, and this had neither. A single injected closure gives the identical test substitution (the test passes a closure that captures the fire handler and triggers it synchronously) at a fraction of the surface: three types collapse to one. The named-protocol idiom reads marginally more explicitly, but "matches an idiom" isn't "needed here."

**Consequence for tests:** the fake scheduler class in the tests becomes a captured closure + a stored fire handler the test invokes directly. Same assertions (recorded armed dates, drive-the-fire), less scaffolding.

### A DB write reschedules the boundary timer, not just `refreshAll()`

**Decision:** The `didSave` observer does two things per save: fire `refreshAll()` **and** recompute+reschedule the boundary timer.

**Why?** `StageCharacterization.nextStageRefreshTime(commitments:now:)` is a pure function of the current commitment set. If a save changes that set, the already-scheduled fire instant can be wrong:
- **Too late:** adding a commitment whose next slot edge is _before_ the currently-scheduled fire would miss that edge until the old (later) fire.
- **Stale:** deleting/archiving/editing the commitment that owned the next edge leaves the timer aimed at an instant that no longer matters (harmless no-op, but the _real_ next boundary isn't scheduled).

So the boundary timer's schedule is derived state over the commitment set, and the observer is the signal that the set changed. Recompute is the timer's existing fire-path operation; the observer simply invokes it too.

**Why no feedback loop?** `refreshAll()` rebuilds notification/LA/widget surfaces but does **not** write to the SwiftData store, so it never re-triggers `didSave`. The observer → refresh/reschedule path terminates.

### Intents keep their explicit awaited `refreshAll()`; the observer replaces only the view calls

**Decision:** The `didSave` observer replaces the fire-and-forget `refreshAll()` in the **5 view sites** (`AddCommitmentView`, `EditCommitmentView`, `ListCommitmentView`, `ArchivedCommitmentsView`, `FinishedCycleReportView`). **Intents** (`CheckInIntent`, `SnoozeIntent`) **keep** their explicit `await CommitmentChangeRefresher.refreshAll()`.

**Why not route Intents through the observer too?** An Intent's `perform()` keeps the app process alive **only until it returns**. The refresh _must_ be awaited inside `perform()` or iOS tears the process down mid-refresh. The observer reacts via a detached `Task`, which `perform()` has no clean way to await without inventing a rendezvous mechanism (a continuation the observer signals) — real complexity added solely to remove two already-correct, already-explicit lines. View saves have no such lifetime constraint (the foreground process isn't going anywhere), so fire-and-forget via the observer is safe there.

**Risk: double-refresh on Intent saves.** With no debounce, an Intent save triggers **two** `refreshAll()` runs — the awaited explicit one, plus the observer's fire-and-forget one. **Mitigation:** both are idempotent, so this is correct-but-wasteful, not buggy. It is exactly the kind of redundancy the deferred debounce (below) would collapse. Accepted for v1.

### No debounce in v1 (noted for later)

**Decision:** The observer fires one `refreshAll()` per `didSave`, with no coalescing.

**Why not debounce now?** Keeps v1 minimal and the commit history clean (one concern per commit). `refreshAll()` is idempotent, so the only cost of a save-burst (e.g. an insert-commitment flow that saves several times, or the Intent double-refresh above) is redundant work, never wrong output.

**Risk: performance under save-bursts.** **Mitigation:** if profiling shows redundant `refreshAll()` runs are a real cost, add a short-window debounce (e.g. coalesce saves within ~300ms into one refresh) as a follow-up. This is explicitly deferred, not forgotten.

### Mutation sites `save()` explicitly so the observer refreshes promptly

**Decision:** Every view mutation site calls `try? modelContext.save()` after mutating. The observer then fires on that `didSave` and rebuilds the surfaces immediately. Add/Edit already did this; Commit 5 adds it to the three sites that previously only mutated + relied on autosave (archive in `ListCommitmentView`, unarchive + delete in `ArchivedCommitmentsView`). `ListCommitmentView` gains an `@Environment(\.modelContext)` for this.

**Why not just rely on autosave?** We tried that first — remove the manual `refreshAll()` and let SwiftData's autosave post `didSave` on its own. **On-device measurement refuted it:** after an archive, `didSave` did not fire for **~15 seconds** (autosave batches; its interval is undocumented and not tunable). An explicit-save site (editing a slot) refreshed **instantly** by contrast. 15s of stale notifications/LA/widget after an archive is perceptible and avoidable, so we save explicitly.

Note this is **the same save either way** — autosave would have persisted these changes regardless; the explicit call only moves the persist (and thus the `didSave`) to _now_ instead of ~15s later. So there is **no extra DB work and no performance cost** — a single-object archive/delete save is cheap, and Add/Edit have always saved on every create/edit without issue.

**On discipline (accepted trade-off).** Requiring `save()` at each mutation site is still a remembered step — but a much _softer_ one than before. The observer already eliminated the dangerous discipline (forget `refreshAll()` → surfaces stay **permanently** stale). What remains is only "remember to `save()` so `didSave` fires _promptly_"; if a future site forgets, autosave still fires `didSave` ~15s later, so a forgotten `save()` is a **latency** bug, not a **correctness** bug. That benign fallback is the safety net that makes the residual discipline low-stakes. Fully eliminating it would require turning autosave off and routing all writes through one `save()`-ing method (repository/wrapper) — a large change that fights SwiftData's "mutate models directly" grain, not worth it for a latency-only concern. A `saveChanges()` helper was considered but rejected: it DRYs the _how_, not the _whether_, and would create two conventions unless the whole app were swept.

### Boundary timer reuses `nextStageRefreshTime`

**Decision:** Compute the next fire instant with `StageCharacterization.nextStageRefreshTime(commitments:now:)` rather than a new boundary calculation.

**Why not a fresh calculation?** That function already folds "next slot edge" and "next cycle/midnight boundary" into a single `Date`, is already unit-tested, and is already the wake policy `NowLiveActivityManager` uses for its BG task. Reusing it keeps the in-app timer and the background wake anchored to the _same_ definition of "next boundary," so foreground and background stay consistent.

**Risk: the psychDay approximation.** `nextStageRefreshTime` approximates the true cycle end with "the next midnight," so the timer may fire once/day at midnight as a harmless no-op recompute. **Mitigation:** none needed — this is an intentional simplicity trade documented on the function itself; a no-op `refreshAll()` at midnight is cheap and idempotent.

### One-shot reschedule vs a repeating `Timer`

**Decision:** The boundary timer is a **one-shot** that reschedules itself after each fire (recomputing `nextStageRefreshTime`), rather than `InAppScheduler`'s repeating fixed-interval `Timer`.

**Why?** The next boundary is not a fixed interval — it depends on the current commitments and the current time. A repeating timer can't express "fire at the next edge, whatever it is." One-shot-then-recompute is the only shape that fires _at_ boundaries.

---

## Major Model Changes

| Entity                                                                         | Change                                                                                                                                                                                  |
| ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **New:** `Wilgo/Features/LiveUpdates/RefreshCoordinator.swift`                 | New `@MainActor` class — thin wiring/lifecycle over a `BoundaryTimer` + a `ModelContextSaveObserver`; both drive `CommitmentChangeRefresher.refreshAll()`.                              |
| **New:** `Wilgo/Features/LiveUpdates/BoundaryTimer.swift`                      | Time-boundary mechanism (one-shot-then-recompute). Owns its `Timer`; test seam is a single injected "arm" closure (no protocol).                                                       |
| **New:** `Wilgo/Features/LiveUpdates/ModelContextSaveObserver.swift`          | Extracted, generic SwiftData `didSave` observer (watch a context, run a closure on save; object-scoped). No Wilgo-specific knowledge.                                                  |
| `Wilgo/WilgoApp.swift`                                                         | Start `RefreshCoordinator` from `init` (replacing the `CatchUpReminder.startHourlyRunWhileActive()` call). Owned as a `private static let` (mirrors `sharedModelContainer`); `start()` is idempotent. |
| `Wilgo/Features/LiveUpdates/Schedulers/CatchUpReminder.swift`                  | Delete `startHourlyRunWhileActive()`, the `scheduler` property, and the in-app-scheduler comment block. CatchUp keeps its `BackgroundRefreshScheduler` conformance and `performWork()`. |
| `Wilgo/Features/Commitments/Form/AddCommitmentView.swift`                      | Remove manual `Task { await refreshAll() }` after `save()`.                                                                                                                             |
| `Wilgo/Features/Commitments/Form/EditCommitmentView.swift`                     | Remove manual `Task { await refreshAll() }` after `save()`.                                                                                                                             |
| `Wilgo/Features/Commitments/ListCommitmentView.swift`                          | Remove manual `Task { await refreshAll() }` after `save()`.                                                                                                                             |
| `Wilgo/Features/Commitments/ArchivedCommitmentsView.swift`                     | Remove the 2 manual `Task { await refreshAll() }` calls after `save()`.                                                                                                                 |
| `Wilgo/Features/Commitments/FinishedCycleReport/FinishedCycleReportView.swift` | No code change — it saves but never called `refreshAll()` (the missing-refresh gap). The observer now covers it automatically.                                                          |
| `Shared/InAppScheduler.swift`                                                  | Becomes unused after CatchUp drops it. **Delete** if no other references remain (grep confirms CatchUp is the sole user).                                                               |

---

## Commit Plan

Every commit must leave the app building and add unit tests for the actual code change (per CLAUDE.md). Tests use the required iPhone 17 simulator via `./test-with-cleanup.sh`.

A note on testability: each unit takes its dependencies as injectable seams — `BoundaryTimer` takes a boundary provider, an `onFire`, and an "arm" closure (the timer seam); `ModelContextSaveObserver` takes the observed context, notification center, and an `onSave` closure. `RefreshCoordinator` forwards these through. This lets every unit be tested without real time passing or hitting `UNUserNotificationCenter`/`ActivityKit`. Main-actor-isolated defaults (e.g. `ModelContext.wilgoMain`) are resolved in init bodies from `nil` sentinels, never as default-argument expressions, because `-default-isolation=MainActor` evaluates default args in a nonisolated context.

This plan builds the new structure as **five focused commits**, each self-contained and independently testable. Commits 1 and 2 are pure standalone units (no dependency between them). Commit 3 wires them. Commit 4 activates the wiring in the app and removes the old hourly timer. Commit 5 removes the now-redundant view-site manual calls.

---

#### Commit 1 — `BoundaryTimer` unit (time-boundary mechanism)

**Create:** `Wilgo/Features/LiveUpdates/BoundaryTimer.swift`

- `@MainActor final class BoundaryTimer`. Owns the one-shot `Timer` directly (no `BoundaryScheduler` protocol — see the closure-seam decision).
- `init(nextBoundary: @escaping () -> Date, onFire: @escaping () async -> Void, arm: ((Date, @escaping () async -> Void) -> Void)? = nil)` — `arm` is the injectable timer seam, defaulting (resolved in the body) to a real main-run-loop one-shot `Timer` that clamps past dates to fire ASAP.
- `schedule()` reads `nextBoundary()` fresh and arms the timer. On fire: run `onFire()`, then `schedule()` again (one-shot-then-recompute, not a fixed interval). `cancel()` invalidates.

**Create:** `WilgoTests/LiveUpdates/BoundaryTimerTests.swift`

- `schedule()` arms to the computed boundary (assert via a test `arm` closure that records the armed `Date`).
- After a fire, it recomputes to the _next_ boundary — provider returns different Dates on successive calls, proving recompute (not a fixed interval).
- `onFire` runs when the timer fires (drive the fire synchronously via the captured handler — no real clock, no `Thread.sleep`).

#### Commit 2 — `ModelContextSaveObserver` unit (generic didSave observer)

**Create:** `Wilgo/Features/LiveUpdates/ModelContextSaveObserver.swift`

- Generic, Wilgo-agnostic `@MainActor final class`: `init(context: ModelContext, center: NotificationCenter = .default, onSave: @escaping () -> Void)`.
- `start()` registers a `ModelContext.didSave` observer scoped via `object: context` (idempotent — no double-register). `stop()`/`deinit` remove it.
- Runs `onSave` on the main actor (`MainActor.assumeIsolated`, valid because the observed context is a main-actor context saved on the main actor — see Open Question).

**Create:** `WilgoTests/LiveUpdates/ModelContextSaveObserverTests.swift`

- A real `save()` on the observed context runs `onSave`.
- A save on a DIFFERENT context does NOT run it (object-scoping).
- `stop()` (and letting it deinit) removes it — a later save is a no-op.
- `start()` is idempotent (second call does not double-register / double-fire).
- Async waits use `await Task.yield()` loops, never `Thread.sleep`. Hold a strong ref to the container for the whole test.

#### Commit 3 — `RefreshCoordinator` wiring (owns + connects the two units)

**Create:** `Wilgo/Features/LiveUpdates/RefreshCoordinator.swift`

- `@MainActor final class` — thin wiring + lifecycle. Builds a `BoundaryTimer` and a `ModelContextSaveObserver` and connects them.
- Public init resolves production defaults in the body: `refreshAction` → `CommitmentChangeRefresher.refreshAll()`; `nextBoundary` → `defaultNextBoundary()` (folds slot edge + cycle boundary via `StageCharacterization.nextStageRefreshTime` over `wilgoMain`'s active commitments); observed context → `wilgoMain`; center → `.default`. Keep `arm`/`nextBoundary`/`refreshAction`/`observedContext`/`center` injectable for tests.
- Wiring: timer `onFire` = refresh; observer `onSave` = fire-and-forget `Task { await refreshAction() }` **and** `boundaryTimer.schedule()` (re-arm, because a DB write can move/invalidate the next boundary — pure function of the commitment set).
- `start()` starts both (idempotent via `didStart`). `stop()` stops both.

**Create:** `WilgoTests/LiveUpdates/RefreshCoordinatorObserverTests.swift`

- Integration over the wired whole: a `save()` triggers the refresh action; a `save()` also re-arms the boundary timer to the newly-computed instant; multiple saves each trigger (no-debounce); object-scoping (save on another context doesn't trigger); `stop()` removes the observer.

#### Commit 4 — Wire `RefreshCoordinator` into `WilgoApp`; remove CatchUp's hourly timer

**Modify:** `Wilgo/WilgoApp.swift` — own the coordinator as a `private static let` (mirrors `sharedModelContainer`, immune to a re-run `init()`), call `.start()` once from `init()` (start is idempotent). Replaces the `CatchUpReminder.startHourlyRunWhileActive()` call.
**Modify:** `Wilgo/Features/LiveUpdates/Schedulers/CatchUpReminder.swift` — delete `startHourlyRunWhileActive()`, the `scheduler` property, and the stale in-app-scheduler comment. CatchUp keeps its `BackgroundRefreshScheduler` conformance + `performWork()`.
**Delete:** `Shared/InAppScheduler.swift` — CatchUp was the sole user (grep-confirmed). Remove its references from `project.pbxproj` (`Shared/` is not a folder-synced group).

**Manual verification:** Launch on iPhone 17 sim. Confirm the app builds/runs and that surfaces refresh when a slot boundary is crossed while foregrounded (Console subsystem `wilgo`).

#### Commit 5 — Remove manual `refreshAll()` from the 5 view sites

**Modify:** `AddCommitmentView.swift`, `EditCommitmentView.swift`, `ListCommitmentView.swift`, `ArchivedCommitmentsView.swift` (×2) — delete the `Task { await refreshAll() }` after the mutation. The three archive/unarchive/delete sites, which previously only mutated + relied on autosave, now call `try? modelContext.save()` so `didSave` fires promptly (see the "Mutation sites `save()` explicitly" decision — on-device showed autosave lagged ~15s). `ListCommitmentView` gains an `@Environment(\.modelContext)` for this. Add/Edit already `save()` explicitly.
**No change (beneficiary):** `FinishedCycleReportView.swift` has a `save()` but _no_ `refreshAll()` call today — the currently-missing-refresh gap. Nothing to remove; the observer now covers it automatically. This commit closes that gap.
**Keep, with a clarifying comment:** `CheckInIntent.swift`, `SnoozeIntent.swift` — their explicit awaited `refreshAll()` stays. The observer also fires on their `save()`, but the observer's refresh is fire-and-forget and could be cut off when the Intent's `perform()` returns and iOS suspends the app; the awaited explicit call guarantees completion (harmless double refresh — `refreshAll()` is idempotent).

**Manual verification:** Launch on iPhone 17 sim. Add/edit/archive a commitment and check in via widget/LA; confirm every surface refreshes exactly as before. Confirm a finished-cycle save now refreshes (previously missed).

---

## Critical Files

| File                                                          | Role                                                |
| ------------------------------------------------------------- | --------------------------------------------------- |
| `Wilgo/Features/LiveUpdates/BoundaryTimer.swift` (new)        | Time-boundary trigger unit (Commit 1)               |
| `Wilgo/Features/LiveUpdates/ModelContextSaveObserver.swift` (new) | Generic `didSave` observer unit (Commit 2)      |
| `Wilgo/Features/LiveUpdates/RefreshCoordinator.swift` (new)   | Thin wiring/lifecycle over the two units (Commit 3) |
| `Wilgo/WilgoApp.swift`                                        | Starts the coordinator; drops CatchUp hourly start (Commit 4) |
| `Wilgo/Features/LiveUpdates/Schedulers/CatchUpReminder.swift` | Loses its in-app hourly timer (Commit 4)            |
| `Shared/Scheduling/StageCharacterization.swift`               | Provides `nextStageRefreshTime` (reused, unchanged) |
| `Shared/InAppScheduler.swift`                                 | Deleted (Commit 4)                                  |

### Dependency Graph

```
Commit 1: BoundaryTimer unit ──┐
                               ├─→ Commit 3: RefreshCoordinator wiring
Commit 2: SaveObserver unit ───┘         |
                                         +─→ Commit 4: wire into WilgoApp, drop CatchUp hourly
                                                 |
                                                 +─→ Commit 5: remove view-site manual calls
```

Commits 1 and 2 are independent. Commit 3 depends on both. Commit 4 depends on 3. Commit 5 depends on 4 (the observer must be live before the manual calls are removed).

---

## Open Questions / Risks (for review)

### `ModelContextSaveObserver` uses `MainActor.assumeIsolated` in the notification callback

The observer's `didSave` handler runs `onSave` inside `MainActor.assumeIsolated { }`. This is correct **only** under the invariant that the observed `ModelContext` is a main-actor context saved on the main actor (true for `wilgoMain`, which is `mainContext`, and for the in-memory test contexts). The invariant is **not enforced by the API** — the init accepts any `ModelContext`. If the observer were ever reused for a context saved off the main actor, `assumeIsolated` would trap at runtime.

For this workstream it's safe (we only ever observe `wilgoMain`). Options if we want to harden it later: (a) make the contract explicit in the type name/docs, (b) hop via `Task { @MainActor in … }` instead of asserting (trades the synchronous re-arm for an async one), or (c) leave as-is. **Decision deferred to 3Sauce's review** — flagging rather than silently choosing.
