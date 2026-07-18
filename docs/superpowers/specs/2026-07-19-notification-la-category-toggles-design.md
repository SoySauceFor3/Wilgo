# Notification & Live Activity Category Toggles — Design

**Date:** 2026-07-19
**Author:** 3Sauce (with Claude)
**Status:** Design — awaiting review

---

## Goal

Add a Settings section with four independent on/off toggles, one per scheduler category in
`Wilgo/Features/LiveUpdates/Schedulers/`:

| Toggle | Category | Owning scheduler |
|---|---|---|
| Slot-start notifications | fire when a commitment's slot opens | `SlotStartNotificationScheduler` |
| Catch-up reminders | nudge chain for behind commitments | `CatchUpReminder` |
| Cycle-end notifications | fire at each cycle boundary | `CycleEndNotificationScheduler` |
| Now Live Activity | lock-screen / Dynamic Island card | `NowLiveActivityManager` |

**Toggle OFF:** that category's notifications/LA are all cancelled — pending *and* currently-active
(a live LA card is ended).

**Toggle ON:** that category is scheduled again by re-running its `refresh()`. Future notifications
are rescheduled and any Live Activity card that *should be showing right now* reappears. Notifications
whose fire time already passed while the toggle was off stay gone (iOS cannot retroactively fire them).

---

## Design Decisions

### 1. Four separate toggles (1:1 with the Schedulers/ folder)

**Decision:** one toggle per category, not a coarser Notifications/LA grouping.

**Why:** maximum user control and a clean mental model that mirrors the code. Each category already
has an independent scheduler with its own owned-ID namespace, so per-category gating is a natural fit.

### 2. Gate lives inside each scheduler, not only in Settings

**Decision:** the enable/disable check happens at each category's work entry point
(`performWork()` for the three `BackgroundRefreshScheduler` conformers; `refresh()` for
`CycleEndNotificationScheduler`, which does not conform). When disabled, the body cancels all owned
notifications / ends all owned LA cards, then returns before scheduling anything.

```
guard AppSettings.<flag> else { <cancel all owned>; return }
```

**Why not gate only in Settings?** Every trigger path must respect the toggle — background wakes
(BGAppRefreshTask), scene-phase refreshes, the `RefreshCoordinator` boundary timer, and SwiftData
`didSave` all funnel through `refresh()` → `performWork()`. Gating only in the Settings handler would
let those paths silently re-populate a disabled category behind the user's back. Gating at the work
entry point makes the toggle authoritative regardless of who triggered the refresh.

**Consequence:** the Settings toggle handler becomes trivial — flip the `AppSettings` flag, then
`Task { await <Scheduler>.refresh() }`. Off → the gate cancels; on → the gate lets refresh repopulate.

### 3. `refresh()` re-queue-first invariant is untouched; background-wake floor unchanged

**Decision:** the `BackgroundRefreshScheduler.refresh()` template
(re-queue next wake FIRST, then `performWork()`) is not modified. `nextWakeEarliestDate` keeps its
normal value even when a category is off.

**Why:** the re-queue-first ordering is a load-bearing crash-safety invariant
(`BackgroundRefreshScheduler.swift`). Adding an "if disabled, skip/defer the wake" branch would
complicate that template for negligible benefit. When off, the app still wakes at the normal cadence
but `performWork()` immediately cancels + returns — a handful of cheap no-op wakes per day, not a
busy loop (iOS grants BG wakes as discrete, throttled events).

**Risk:** a disabled catch-up category still gets ~hourly no-op wakes. **Mitigation:** accepted —
the cost is trivial and it keeps the gate confined to `performWork()` with zero changes to the
wake-policy getters or the documented invariant.

### 4. Toggle-on = just re-run `refresh()` (no re-firing of missed notifications)

**Decision:** re-enabling calls the category's `refresh()`. Its existing cancel-then-rebuild body
reschedules everything upcoming; for Live Activity, the planner re-creates any card whose slot is
open right now. We do **not** attempt to surface notifications whose fire time passed while off.

**Why:** matches how every scheduler already works (idempotent rebuild from current state). Re-firing
missed notifications would require bespoke per-scheduler logic and depart from the cancel-then-rebuild
model. iOS cannot retroactively fire a past-dated notification anyway.

### 5. Defaults ON (absent key = enabled)

**Decision:** each flag returns `true` when its UserDefaults key is absent.

**Why:** existing users must keep current behavior after the update — no silent disabling of
notifications they already rely on. Mirrors the established `weekStartsOnMonday` /
`includeActiveSlotsInCatchUp` getter pattern in `AppSettings`.

---

## Architecture Summary

Three moving parts:

1. **`AppSettings` (Shared/AppSettings.swift):** four new `…EnabledKey` string constants + four
   computed `Bool` getters, each defaulting to `true` when the key is absent. Same idiom as the
   existing settings.

2. **The gate (each scheduler):** an early guard at the work entry point. When the flag is off:
   - `SlotStartNotificationScheduler.performWork()` → remove all pending requests with the
     slot-start prefix, return.
   - `CatchUpReminder.performWork()` → remove all `allNotificationIDs`, return.
   - `CycleEndNotificationScheduler.refresh()` → remove all `allNotificationIDs`, return.
   - `NowLiveActivityManager.performWork()` → reconcile against an **empty plan** so
     `LiveActivityRefresher` ends every seated card via its existing `endOrphans` diff, return.

3. **Settings UI (`SettingsView.swift`):** a new section with four `Toggle`s bound to the flags;
   each `set` closure writes the flag then kicks `Task { await <Scheduler>.refresh() }`.

Data flow on toggle:
```
User flips Toggle
  → AppSettings.<flag> written to UserDefaults
  → Task { await <Scheduler>.refresh() }
      → refresh() re-queues next wake (unchanged), then performWork()
          → guard AppSettings.<flag>:
               OFF → cancel all owned notifications / end all owned LA cards → return
               ON  → normal cancel-then-rebuild (reschedules future + should-be-now)
```

---

## Live Activity "cancel all" detail

`LiveActivityRefresher` has no dedicated end-all helper today, but its `refresh()` already ends any
seated card that is absent from the plan (`endOrphans`). Reconciling against an **empty plan** ends
every seated Wilgo card. Implementation options (decide at plan time):

- **A (preferred):** add `LiveActivityRefresher.endAll(context:)` that reuses the end path — explicit
  and self-documenting.
- **B:** in `NowLiveActivityManager.performWork()`, when disabled, call the existing reconcile with a
  forced-empty plan.

Both end pending *and* live cards (the diff treats `.active`, `.stale`, and `.pending` as seated).

---

## Testing

Following the existing `AppSettingsCatchUpTests` / scheduler-test idioms:

1. **`AppSettings` getters** — one serialized suite per flag: absent → `true`; stored `true` → `true`;
   stored `false` → `false`. (Restore the key in `defer`.)
2. **Gate decision** — assert that when the flag is off, the category's owned-ID cancel list is what
   gets removed and no new requests are produced; when on, normal scheduling occurs. Test the pure
   decision/grouping functions directly where possible (as the current scheduler tests do), avoiding
   reliance on the live `UNUserNotificationCenter`.
3. **LA empty-plan end path** — assert the disabled branch produces an "end all seated" reconcile
   (empty plan → all seated cards in `toEnd`).

---

## Out of Scope (YAGNI)

- Re-firing notifications missed while a toggle was off.
- Changing background-wake cadence when a category is off.
- A master "all notifications" switch (the OS already provides one in system Settings).
- Per-commitment notification toggles.
