# Notification & Live Activity Category Toggles — Implementation Plan

**PRD:** [Notification on and off](https://app.notion.com/p/notification-on-and-off-3664b58e32c38042ad5bcd8a792b3f2b?source=copy_link)
**Tracking:** [Notification on and off](https://app.notion.com/p/notification-on-and-off-3664b58e32c38042ad5bcd8a792b3f2b?source=copy_link)
**Tag**: #notificationToggles

---

## Context

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
whose fire time already passed while off stay gone (iOS cannot retroactively fire them).

---

## Architecture Summary

Three moving parts:

1. **`AppSettings` (Shared/AppSettings.swift):** four new `…EnabledKey` string constants + four
   computed `Bool` getters, each defaulting to `true` when the key is absent. Same idiom as the
   existing `weekStartsOnMonday` / `includeActiveSlotsInCatchUp`.

2. **The gate (each scheduler):** an early guard at the category's work entry point — `performWork()`
   for the three `BackgroundRefreshScheduler` conformers, `refresh()` for `CycleEndNotificationScheduler`
   (which does not conform). When the flag is off: cancel all owned notifications / end all owned LA
   cards, then return before scheduling anything.

   ```
   guard AppSettings.<flag> else { <cancel all owned>; return }
   ```

3. **Settings UI (`SettingsView.swift`):** a new section with four `Toggle`s bound to the flags; each
   `set` closure writes the flag, then kicks `Task { await <Scheduler>.refresh() }`.

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

Because the gate lives at the work entry point, **every** trigger path respects the toggle: background
wakes (BGAppRefreshTask), scene-phase refresh, the `RefreshCoordinator` boundary timer, and SwiftData
`didSave` all funnel through `refresh()` → `performWork()`.

---

## Design Decisions

### 1. Four separate toggles (1:1 with the Schedulers/ folder)

**Decision:** one toggle per category, not a coarser Notifications/LA grouping.

**Why not fewer toggles?** A 2- or 3-way grouping is simpler UI but coarser control. Each category
already has an independent scheduler with its own owned-ID namespace, so per-category gating is a
natural, low-cost fit and gives the user maximum control.

**Risk:** four rows is slightly more UI. Mitigation: negligible — a single Form section.

### 2. Gate lives inside each scheduler, not only in Settings

**Decision:** the enable/disable check happens at each category's work entry point. When disabled, the
body cancels all owned notifications / ends all owned LA cards, then returns before scheduling.

**Why not gate only in Settings?** Every trigger path must respect the toggle. Gating only in the
Settings handler would let background wakes and DB-save refreshes silently re-populate a disabled
category behind the user's back.

**Risk:** the flag is read in more places. Mitigation: it's a single-line guard reading a centralized
`AppSettings` getter — cheap and consistent.

### 3. Toggle-on = just re-run `refresh()` (no re-firing of missed notifications)

**Decision:** re-enabling calls the category's `refresh()`. Its existing cancel-then-rebuild body
reschedules everything upcoming; for Live Activity, the planner re-creates any card whose slot is open
right now. We do **not** attempt to surface notifications whose fire time passed while off.

**Why not re-fire missed ones?** It would require bespoke per-scheduler logic and depart from the
cancel-then-rebuild model. iOS cannot retroactively fire a past-dated notification anyway.

**Risk:** a user who re-enables expects "the one I missed" — they won't get it. Mitigation: acceptable;
the should-be-now LA card *does* reappear, which covers the only currently-relevant surface.

### 4. Background-wake floor unchanged; the `refresh()` re-queue stays unconditional

**Decision:** the `BackgroundRefreshScheduler.refresh()` template (re-queue next wake FIRST, then
`performWork()`) is not modified. `nextWakeEarliestDate` keeps its normal value even when a category
is off. The on/off check lives only inside `performWork()`.

**Why not skip/defer the wake when off?** See the full reasoning below — in short, it would couple
correctness to a hidden contract and risk a silent, permanent "background updates never come back"
failure.

**Risk:** a disabled catch-up category still gets ~hourly no-op wakes. Mitigation: accepted — the cost
is trivial (a fetch-flag → cancel → return), and it keeps the gate confined to `performWork()` with
zero changes to the wake-policy getters or the documented invariant.

#### Why we keep the BG re-queue unconditional when a category is OFF (the reasoning, in full)

An iOS `BGAppRefreshTask` is a **one-shot**: each granted wake consumes the single pending request,
and iOS will only launch us again if a *new* request is queued. The only reliable place to queue that
next request is while we are currently awake and running — so every wake must "re-arm" the chain
(call `scheduleBackgroundTask()`) or background updates for that category go **dark** until the next
foreground launch. `refresh()` therefore re-arms FIRST, unconditionally, then runs `performWork()`:
even if iOS kills the app mid-`performWork()` (background execution is hostile — the app can be
suspended/killed at any `await`), the next wake is already queued, so the chain survives. That is the
"crash-safety invariant."

We deliberately do **not** add an "if disabled, skip the re-queue" branch, even though it would
eliminate the no-op wakes and could be written correctly today. Two reasons:

1. **It couples today's correctness to a hidden contract.** If OFF skipped re-arming, then the *only*
   thing that re-arms the chain is the Settings toggle-on handler calling `refresh()`. "Toggle on
   works" would secretly depend on "every re-enable path remembered to call `refresh()`."
2. **The future failure is silent and permanent.** If any later re-enable path (a debug menu, an
   onboarding step, a migration) flips the flag but forgets to call `refresh()`, the chain stays dark
   forever — no crash, no error, notifications just quietly never return. That is the worst kind of
   bug.

Keeping the re-queue unconditional means the flag can **never** disarm the chain: the category always
wakes, and the flag only decides whether that wake *does anything*. Each wake re-reads the flag fresh,
so the behavior is self-correcting regardless of how the flag was last changed. The cost — a few cheap
no-op wakes per day — is a small, bounded price for removing an entire class of future footguns.

### 5. Defaults ON (absent key = enabled)

**Decision:** each flag returns `true` when its UserDefaults key is absent.

**Why not default off?** Existing users must keep current behavior after the update — no silent
disabling of notifications they already rely on. Mirrors the established getter pattern in
`AppSettings`.

### 6. Live Activity "cancel all" via an explicit `endAll` helper (Option A)

**Decision:** add `LiveActivityRefresher.endAll(context:)` that ends every seated Wilgo card, and call
it from `NowLiveActivityManager.performWork()` when the flag is off.

**Why not reconcile against a forced-empty plan (Option B)?** Option B reuses the existing diff
(empty plan → all seated cards land in `toEnd` → ended) with no new surface. But a named `endAll` is
self-documenting at the call site and doesn't rely on the reader knowing the diff semantics. Both end
pending *and* live cards (the diff treats `.active`, `.stale`, `.pending` as seated).

**Risk:** slight duplication of the end path. Mitigation: `endAll` delegates to the same
`activity.end(_:dismissalPolicy:)` calls the reconcile already uses.

> **CONFIRM AT IMPLEMENTATION:** 3Sauce to confirm Option A over Option B before Commit 5.

---

## Major Model Changes

No SwiftData model changes. Only `AppSettings` (UserDefaults keys) and scheduler/UI code.

| Entity | Change |
| ------ | ------ |
| `Shared/AppSettings.swift` | Add 4 `…EnabledKey` constants + 4 computed `Bool` getters (default `true`) |
| `Wilgo/Features/LiveUpdates/Schedulers/SlotStartNotificationScheduler.swift` | Gate + extract owned-ID cancel |
| `Wilgo/Features/LiveUpdates/Schedulers/CatchUpReminder.swift` | Gate + owned-ID cancel |
| `Wilgo/Features/LiveUpdates/Schedulers/CycleEndNotificationScheduler.swift` | Gate in `refresh()` |
| `Wilgo/Features/LiveUpdates/Schedulers/NowLiveActivity/NowLiveActivityManager.swift` | Gate → `endAll` |
| `Wilgo/Features/LiveUpdates/Schedulers/NowLiveActivity/LiveActivityRefresher.swift` | New `endAll(context:)` |
| `Wilgo/Features/Settings/SettingsView.swift` | New "Notifications & Live Activity" section |

---

## Commit Plan

Grouped into three phases: settings foundation → gates → UI. The UI commit is small and purely wires
existing flags to `refresh()`, so it can land right after Phase 1 for manual verification, in parallel
with the Phase 2 gate commits.

---

### Phase 1 — AppSettings foundation

The goal is to add the four flags and their tests so every downstream commit can read them.

#### Commit 1 — Add four category-enabled flags to AppSettings

**Modify:** `Shared/AppSettings.swift` — add, mirroring the existing getters:

```swift
static let slotStartNotificationsEnabledKey = "slotStartNotificationsEnabled"
static var slotStartNotificationsEnabled: Bool { enabledDefaultingTrue(slotStartNotificationsEnabledKey) }

static let catchUpRemindersEnabledKey = "catchUpRemindersEnabled"
static var catchUpRemindersEnabled: Bool { enabledDefaultingTrue(catchUpRemindersEnabledKey) }

static let cycleEndNotificationsEnabledKey = "cycleEndNotificationsEnabled"
static var cycleEndNotificationsEnabled: Bool { enabledDefaultingTrue(cycleEndNotificationsEnabledKey) }

static let nowLiveActivityEnabledKey = "nowLiveActivityEnabled"
static var nowLiveActivityEnabled: Bool { enabledDefaultingTrue(nowLiveActivityEnabledKey) }

/// Reads a Bool that defaults to `true` (enabled) when the key is absent.
private static func enabledDefaultingTrue(_ key: String) -> Bool {
    UserDefaults.standard.object(forKey: key) == nil ? true : UserDefaults.standard.bool(forKey: key)
}
```

**Create:** `WilgoTests/Settings/AppSettingsCategoryTogglesTests.swift` — one serialized suite; for
each flag: absent → `true`, stored `true` → `true`, stored `false` → `false` (restore key in `defer`,
per `AppSettingsCatchUpTests`).

---

### Phase 2 — Scheduler gates (parallel after Commit 1)

The goal is to make each scheduler cancel-and-return when its flag is off. Commits 2–5 are independent
of each other (different files) and can be parallelized after Commit 1.

#### Commit 2 — Gate SlotStartNotificationScheduler

**Modify:** `SlotStartNotificationScheduler.swift` — at the top of `performWork()`:

```swift
guard AppSettings.slotStartNotificationsEnabled else {
    await removeOwnedPending()
    return
}
```

Extract the existing prefix-filtered removal (currently inline in `performWork`) into a
`removeOwnedPending()` helper so both the gate and the normal rebuild use it.

**Test:** `SlotStartNotificationSchedulerTests` — assert the decision path: with the flag off, no
requests are produced; the removal targets only the slot-start-prefixed IDs.

#### Commit 3 — Gate CatchUpReminder

**Modify:** `CatchUpReminder.swift` — at the top of `performWork()`:

```swift
guard AppSettings.catchUpRemindersEnabled else {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: allNotificationIDs)
    return
}
```

(`allNotificationIDs` already exists.)

**Test:** `CatchUpReminderTests` — off ⇒ `fireDates`/scheduling path not entered; the cancel list
equals `allNotificationIDs`.

#### Commit 4 — Gate CycleEndNotificationScheduler

**Modify:** `CycleEndNotificationScheduler.swift` — at the top of `refresh()` (it does not conform to
`BackgroundRefreshScheduler`, so the gate goes in its own entry point):

```swift
guard AppSettings.cycleEndNotificationsEnabled else {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: allNotificationIDs)
    return
}
```

**Test:** `CycleEndNotificationSchedulerTests` — off ⇒ no `activeKinds` scheduling; cancel list equals
`allNotificationIDs`.

#### Commit 5 — Gate NowLiveActivityManager + `endAll`

**Modify:** `LiveActivityRefresher.swift` — add:

```swift
@MainActor
static func endAll(context: ModelContext) async {
    for activity in seatedActivities() {
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}
```

**Modify:** `NowLiveActivityManager.swift` — in the serialized `performWork()` body, gate the
reconcile:

```swift
if AppSettings.nowLiveActivityEnabled {
    await LiveActivityRefresher.refresh(context: ModelContext.wilgoMain)
} else {
    await LiveActivityRefresher.endAll(context: ModelContext.wilgoMain)
}
```

(Keep the existing serialization wrapper unchanged.)

**Test:** `LiveActivityRefresher` end-path test — with seated cards present, `endAll` ends every seated
card. Follows existing planner/refresher test idioms.

> Depends on the Option A/B confirmation in Design Decision 6.

---

### Phase 3 — Settings UI (parallel after Commit 1; verify early)

The goal is to expose the toggles. Small and self-contained.

#### Commit 6 — Add "Notifications & Live Activity" settings section

**Modify:** `SettingsView.swift` — add four `@AppStorage` bindings and a new `Section` with four
`Toggle`s. Each toggle's write triggers the matching refresh — mirroring the existing
`Task { await CycleEndNotificationScheduler.refresh() }` pattern in the week-start handler. Concretely,
each `Toggle` uses a `Binding` whose `set` writes the `@AppStorage` value then runs
`Task { await <Scheduler>.refresh() }`:

```swift
Section {
    Toggle("Slot-start notifications", isOn: /* binding → write + SlotStartNotificationScheduler.refresh() */)
    Toggle("Catch-up reminders",       isOn: /* binding → write + CatchUpReminder.refresh() */)
    Toggle("Cycle-end notifications",  isOn: /* binding → write + CycleEndNotificationScheduler.refresh() */)
    Toggle("Now Live Activity",        isOn: /* binding → write + NowLiveActivityManager.refresh() */)
} header: {
    Text("Notifications & Live Activity")
} footer: {
    Text("Turn a category off to cancel all of its pending and active alerts. Turn it back on to reschedule.")
}
```

**Manual verification (critical):** Launch on iPhone 17 (iOS 26.4), UDID
`4492FF84-2E83-4350-8008-B87DE7AE2588`. For each toggle: turn off → confirm the category's pending
notifications are cleared (and, for LA, the live card disappears); turn on → confirm future
notifications reschedule and a should-be-now LA card reappears.

---

## Critical Files

| File | Role |
| ---- | ---- |
| `Shared/AppSettings.swift` | 4 flags + getters (foundation) |
| `SlotStartNotificationScheduler.swift` | Gate |
| `CatchUpReminder.swift` | Gate |
| `CycleEndNotificationScheduler.swift` | Gate (own `refresh()`) |
| `NowLiveActivityManager.swift` | Gate → `endAll` |
| `LiveActivityRefresher.swift` | New `endAll` |
| `SettingsView.swift` | Toggle UI |

### Dependency Graph

```
Commit 1: AppSettings flags + tests
    |
    +-- Commit 2: Gate SlotStart              [parallel after 1]
    +-- Commit 3: Gate CatchUp                [parallel after 1]
    +-- Commit 4: Gate CycleEnd               [parallel after 1]
    +-- Commit 5: Gate NowLiveActivity+endAll [parallel after 1]
    +-- Commit 6: Settings UI section         [parallel after 1; verify early]
```

Commits 2–6 are independent of each other (distinct files) and can be parallelized after Commit 1.
Commit 6 is worth landing first among them so the toggles can be exercised manually while the gate
commits are in flight.
