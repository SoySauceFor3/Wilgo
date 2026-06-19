# Change to use LiveActivityIntent — Implementation Plan

**PRD:** None (decided in-conversation — this is an architecture/correctness refactor, not a new user-facing feature; behavior should be unchanged-or-better)
**Tracking:** [Change to use LiveActivityIntent](https://www.notion.so/Change-to-use-LiveActivityIntent-3824b58e32c380e39bdbc058a039afc5?source=copy_link)
**Tag:** `#LiveActivityIntent`

---

## Context

The Now **Live Activity** (LA) intermittently fails to advance after a check-in: when a commitment's
goal is met, that commitment should disappear from the LA and the next-up commitment should take its
place, but sometimes it doesn't update at all.

`CheckInIntent` and `SnoozeIntent` are `AppIntent`s triggered from `Button(intent:)` in **two**
surfaces:

- the **home-screen widget** (`WidgetExtension/CurrentCommitmentWidget.swift`), and
- the **Now Live Activity** (`WidgetExtension/NowLiveActivity.swift`).

### Root-cause hypothesis (the "why" we change to LiveActivityIntent)

The bug is a **wrong-process + cross-container-staleness** problem, not a logic bug. The chain:

1. **Which process runs `perform()`?** For a plain `AppIntent`, the system rule is: run in the **app
   process if the app is running and not suspended, otherwise the widget-extension process.** Today
   the intents are members of the **WidgetExtension target only**, so when the app is suspended
   (the normal case on the Lock Screen) `perform()` runs in the **extension**.

2. **`Activity.activities` is per-process.** A Live Activity is owned by the process that started it.
   The app started ours (in `NowLiveActivityManager.apply()`), so only the **app** process sees it in
   `Activity<NowAttributes>.activities`. In the extension that array is **empty**, so
   `activity.update(...)` there silently no-ops.

3. **Separate `ModelContainer` per process.** The extension opens its **own** `ModelContainer` on the
   shared store file. A check-in written there is not deterministically/immediately visible to the
   app's live `mainContext`, so even when the app later recomputes, it can read stale data.

4. **The Darwin-ping workaround can't save it.** Today the extension writes the check-in, then posts a
   Darwin notification (`liveActivitySync`) hoping the **app** process will wake and refresh the LA.
   But if the app is suspended/killed, that observer is dead → the ping is dropped → the LA never
   advances.

**Why intermittent (and why "it works sometimes" supports — not refutes — this hypothesis):** the
outcome depends on app/process state at tap time. App foreground/recently-active → app process alive,
data fresh, Darwin observer fires → works. App suspended → extension runs the intent, ping dropped,
stale container → fails. Logic bugs fail every time; process/staleness races fail *sometimes*. The
intermittency is the signature of this class of bug.

### The fix: `LiveActivityIntent`

Adopting the `LiveActivityIntent` protocol changes the process rule to **always run `perform()` in the
app's process** — even when the app is suspended or not running (the system wakes the app process in
the **background**; it does **not** foreground the app). This single change collapses suspects (1),
(2), and (3): the LA handle is visible, the write happens in the app's live context, and the Darwin
ping becomes unnecessary.

**Requirement:** the "run in app process" guarantee only takes effect if the **intent type is a member
of the app target.** Apple: *"if you add a shared LiveActivityIntent across both the main app target
and the widget extension, only the main app's intent will be executed."* Our intents are currently
app-target **non-members**, so membership must change (see Design Decisions).

### Honest framing

This is treated as **a refactor that very likely fixes the bug, not a confirmed fix.** It is worth
doing regardless of outcome because it removes three confounding variables (wrong process, stale
container, dead-app ping) in one move. If the bug survives, the post-migration baseline is
deterministic (`perform()` always app-side) and far easier to debug. We therefore **keep
verification on-device as part of the plan** and only declare success after observing the LA advance.

#### Sources

- [LiveActivityIntent — Apple Developer Documentation](https://developer.apple.com/documentation/AppIntents/LiveActivityIntent)
- [Can Live Activities be updated via `activity.update` in extensions? — Apple Developer Forums](https://developer.apple.com/forums/thread/735382)
- [Forcing an AppIntent to run in the main app process — Zach Waugh](https://zachwaugh.com/posts/forcing-appintent-to-run-in-main-app-process)
- [Interactivity with Live Activities and App Intents — Ben Frearson](https://bfrearson.github.io/blog/ios-live-activties/)

---

## Architecture Summary

Move `CheckInIntent` and `SnoozeIntent` into `Shared/` (so both targets compile a single type
definition), conform them to `LiveActivityIntent`, and update the LA **in-process** from `perform()`
by reusing `NowLiveActivityManager`'s recompute path. Because `perform()` now always runs app-side:

- the SwiftData write uses the app's `mainContext` (same object graph as `@Query` / the schedulers) —
  no cross-container staleness;
- `Activity<NowAttributes>.activities` is populated, so the LA can be updated/ended directly;
- the Darwin `liveActivitySync` ping and its app-side observer are removed (the in-process call
  replaces them).

```
BEFORE (plain AppIntent, extension-only)
  Tap Done on LA (app suspended)
    → perform() runs in EXTENSION
    → own ModelContainer write
    → Activity.activities EMPTY here → can't update
    → post Darwin ping → app is dead → dropped
    → LA never advances                         ❌ intermittent

AFTER (LiveActivityIntent, in Shared/, app-target member)
  Tap Done on LA (app suspended)
    → system wakes APP process (background) → perform() runs APP-side
    → write via app mainContext (fresh object graph)
    → NowLiveActivityManager.apply(): recompute current → update/end the running Activity directly
    → LA advances deterministically             ✅
```

The home-screen widget button uses the same intent type, so it gets the same app-process treatment —
strictly better than today (its writes also stop going through a separate stale container).

---

## Design Decisions

### Adopt `LiveActivityIntent` instead of plain `AppIntent`

**Decision:** Conform `CheckInIntent` and `SnoozeIntent` to `LiveActivityIntent`.

**Why?** It guarantees `perform()` runs in the app process (background, no foreground), which is the
only place both the LA handle and the live `mainContext` exist. This is the supported, documented way
to update a running LA from an intent without push.

**Why not keep the Darwin-ping workaround?** It pings a process that is usually suspended when the user
taps from the Lock Screen, so the refresh is dropped — exactly the failure we see.

**Why not APNs Live Activity push?** Far larger lift (push token plumbing + server) and overkill for a
local check-in button. Can be revisited later if background LA rendering proves unreliable even with
`LiveActivityIntent` (see Risk below).

**Risk:** Some developers report background LA *render* updates being intermittent even with
`LiveActivityIntent` (the app process is woken and `perform()` runs, but ActivityKit occasionally
defers the visible update until next foreground). **Mitigation:** This is still vastly more reliable
than the current dead-ping path; verify on-device (success criteria below). If it proves insufficient,
APNs LA push is the documented next step — out of scope here.

### Move the intent files to `Shared/` (and into both targets)

**Decision:** Move `CheckInIntent.swift` and `SnoozeIntent.swift` from `WidgetExtension/` into
`Shared/` (e.g. `Shared/Intents/`), and ensure `Shared/Intents/` is a member of **both** the app and
the WidgetExtension targets (the app target already syncs `Models` and `Scheduling` from `Shared`; add
the new folder the same way).

**Why move, rather than just add the existing WidgetExtension files to the app target?** The
"run in app process" guarantee requires the intent type to exist in the app bundle. The cleanest way
to have **one** type compiled into both targets is to put it in a shared folder both compile. Adding a
WidgetExtension-folder file to the app target also works mechanically, but mixing widget-only views
(`NowLiveActivity.swift`, `CurrentCommitmentWidget.swift`) with shared logic in one folder is messier
and makes target membership harder to reason about. `Shared/` is already the home for cross-process
code (`CommitmentAndSlot`, models, `NowAttributes`, `CheckInSource`), so this matches the existing
architecture.

**Why not duplicate the type in each target?** Two separately-compiled `CheckInIntent` types would
have different type identity; the system would not treat them as the same intent, defeating the
purpose and risking duplicate-symbol / "intent not found" issues. Single shared definition only.

**Risk:** Xcode synchronized-file-group (`PBXFileSystemSynchronizedRootGroup`) membership must be set
correctly so the new `Shared/Intents/` folder compiles into both targets and is **not** excluded for
either. **Mitigation:** Verify both targets build and that the LA + widget buttons still resolve the
intent (manual verification). This is a project-file change — flagged for manual confirmation in Xcode.

### Update the LA in-process from `perform()` by reusing `NowLiveActivityManager`

**Decision:** After the SwiftData write, call the existing app-side recompute that updates/ends the
running Activity (the `NowLiveActivityManager.apply()` path), instead of posting the Darwin ping.

**Why?** `apply()` already contains the correct "recompute current commitment → update or end the
Activity" logic. Reusing it keeps a single source of truth for LA content and avoids duplicating the
ActivityKit calls inside the intents.

**Why not call `Activity.update` directly in the intent?** That would duplicate the content-state
construction already in `NowLiveActivityManager`. Better to route through the manager.

**Mechanics to settle during implementation:** `apply()` is currently `private`. Expose a minimal
app-side entry point the intent can call (e.g. make a small `@MainActor static func refreshLiveActivity()`
that awaits `apply()`, or widen `apply`'s access). The intent file is shared, but the
`NowLiveActivityManager`/ActivityKit update call must only execute app-side — guard with the same
mechanism that keeps ActivityKit out of the extension build, or call the manager only from the
app-process code path. Confirm `import ActivityKit` availability per target.

**Risk:** Calling the manager from a shared file could pull app-only symbols into the extension build.
**Mitigation:** Keep ActivityKit/`NowLiveActivityManager` references behind app-target-only access;
the intent's shared body does the write, and the LA refresh is invoked through an app-side hook. Verify
the extension still builds.

### Keep `WidgetCenter.reloadTimelines(...)` in `perform()`

**Decision:** Retain the home-screen-widget timeline reload after the write.

**Why?** The home-screen widget reads snapshots from the store; it still needs a reload to reflect the
new check-in. Unrelated to the LA path; leave intact.

### Remove the Darwin `liveActivitySync` ping + app-side observer

**Decision:** Remove the `CFNotificationCenterPostNotification(... liveActivitySync ...)` calls from
both intents and the matching observer registration in
`NowLiveActivityManager.startObservingIntentNotifications()` (and its call site in `WilgoApp`).

**Why?** The in-process `apply()` call replaces it. Leaving a dead ping/observer is misleading.

**Risk:** Some other code path may rely on the ping. **Mitigation:** Grep confirms only the two
intents post it and only `NowLiveActivityManager` observes it; safe to remove together.

---

## Major Model Changes

No SwiftData model changes. Code-location + protocol-conformance + project-membership changes only.

| Entity | Change |
| --- | --- |
| **Move:** `WidgetExtension/CheckInIntent.swift` → `Shared/Intents/CheckInIntent.swift` | Conform to `LiveActivityIntent`; remove Darwin ping; refresh LA in-process |
| **Move:** `WidgetExtension/SnoozeIntent.swift` → `Shared/Intents/SnoozeIntent.swift` | Conform to `LiveActivityIntent`; remove Darwin ping; refresh LA in-process |
| `Wilgo.xcodeproj/project.pbxproj` | Add `Shared/Intents/` to app target **and** WidgetExtension target synchronized groups |
| `Wilgo/Features/Notifications/NowLiveActivityManager.swift` | Expose an app-side LA-refresh entry point; remove `startObservingIntentNotifications` Darwin observer |
| `Wilgo/WilgoApp.swift` | Remove the `startObservingIntentNotifications()` call |
| `Shared/WilgoConstants.swift` | Remove `liveActivitySyncNotification` constant (after both intents stop using it) |

---

## Commit Plan

Each commit is self-contained: app + extension build, no new failing tests. Because `perform()` talks
to the real store/ActivityKit asynchronously, the genuinely new behavior is verified **on device**
(per the existing testing convention for these schedulers). Unit tests cover what is pure/deterministic
(intent parameter round-trip, recompute logic already covered by `CommitmentAndSlot` tests).

---

### Phase 1 — Relocate intents into Shared (no behavior change)

Goal: get a **single** intent type compiled into both targets, still as plain `AppIntent`, behavior
identical. This isolates the risky project-file/membership change from the protocol change.

#### Commit 1 — move CheckInIntent & SnoozeIntent to `Shared/Intents/` (both-target membership)

**Move:** `WidgetExtension/CheckInIntent.swift` → `Shared/Intents/CheckInIntent.swift`
**Move:** `WidgetExtension/SnoozeIntent.swift` → `Shared/Intents/SnoozeIntent.swift`
(No code change yet — still `AppIntent`, still posts Darwin ping.)

**Modify:** `Wilgo.xcodeproj/project.pbxproj` — add `Shared/Intents/` as a synchronized group member
of both the `Wilgo` (app) and `WidgetExtension` targets.

**Manual verification (critical):** In Xcode, confirm both `CheckInIntent.swift` and
`SnoozeIntent.swift` show **Target Membership = Wilgo + WidgetExtension**. Build both targets. Launch
on iPhone 17 (iOS 26.4, UDID `4492FF84-2E83-4350-8008-B87DE7AE2588`). Home-screen widget + LA buttons
still check in / snooze exactly as before (still via the old ping path). No behavior change expected.

*No dependency. Establishes the shared, dual-target type before changing its protocol.*

---

### Phase 2 — Adopt LiveActivityIntent + in-process LA refresh

Goal: flip the process behavior and replace the Darwin ping with an in-process LA refresh.

#### Commit 2 — expose an app-side LA-refresh entry point on NowLiveActivityManager

**Modify:** `Wilgo/Features/Notifications/NowLiveActivityManager.swift` — add a minimal
`@MainActor static func refreshLiveActivity() async` (or widen `apply()` access) that performs the
existing recompute-and-update/end. No call-site changes yet; pure addition.

**Test:** No new behavior to unit-test beyond what `CommitmentAndSlot` already covers; ensure existing
tests still pass.

*Depends on nothing new; prepares the hook Commit 3 calls.*

#### Commit 3 — conform CheckInIntent to LiveActivityIntent; refresh LA in-process; drop ping

**Modify:** `Shared/Intents/CheckInIntent.swift`

- `struct CheckInIntent: LiveActivityIntent` (was `AppIntent`).
- After `try context.save()`, invoke the app-side `NowLiveActivityManager.refreshLiveActivity()`
  (app-process-only path) instead of posting the Darwin ping.
- Keep `WidgetCenter.shared.reloadTimelines(...)`.

**Test:** `WilgoTests` — assert `CheckInIntent(commitmentId:source:)` round-trips its parameters; the
store write + LA update is **manual verification** (intents hit the real store/ActivityKit).

**Manual verification (critical):** On device, with a Now LA showing a commitment whose goal is one
check-in away: tap **Done** on the **Lock Screen LA while the app is fully backgrounded/suspended**.
Expected: the completed commitment disappears and the next-up commitment appears (or the LA ends if
none remain). Repeat from the **home-screen widget** button. Confirm check-in persists and widget
refreshes.

#### Commit 4 — conform SnoozeIntent to LiveActivityIntent; refresh LA in-process; drop ping

**Modify:** `Shared/Intents/SnoozeIntent.swift` — same treatment as Commit 3 (snooze write → in-process
LA refresh, drop ping, keep widget reload).

**Test:** parameter round-trip for `SnoozeIntent(slotId:)`; store/LA behavior = manual verification.

**Manual verification:** On device, tap **Snooze** on the Lock Screen LA while the app is suspended;
the snoozed slot's commitment updates/leaves the LA appropriately.

---

### Phase 3 — Remove the dead Darwin path

Goal: delete the now-unused ping/observer once both intents no longer use it.

#### Commit 5 — remove Darwin liveActivitySync observer + constant

**Modify:** `Wilgo/Features/Notifications/NowLiveActivityManager.swift` — remove
`startObservingIntentNotifications()` (the Darwin observer).
**Modify:** `Wilgo/WilgoApp.swift` — remove the `startObservingIntentNotifications()` call.
**Modify:** `Shared/WilgoConstants.swift` — remove `liveActivitySyncNotification`.

**Pre-check:** Grep confirms no remaining references to `liveActivitySync` /
`startObservingIntentNotifications` outside these files.

**Manual verification:** Re-run the Phase 2 checks; LA still advances (proving the in-process path,
not the removed ping, is doing the work).

---

## Critical Files

| File | Role |
| --- | --- |
| `Shared/Intents/CheckInIntent.swift` (moved) | LiveActivityIntent; in-process check-in + LA refresh |
| `Shared/Intents/SnoozeIntent.swift` (moved) | LiveActivityIntent; in-process snooze + LA refresh |
| `Wilgo.xcodeproj/project.pbxproj` | Dual-target membership for `Shared/Intents/` |
| `Wilgo/Features/Notifications/NowLiveActivityManager.swift` | App-side LA-refresh entry point; remove Darwin observer |
| `Wilgo/WilgoApp.swift` | Drop observer registration |
| `Shared/WilgoConstants.swift` | Drop `liveActivitySyncNotification` |

### Dependency Graph

```
Commit 1: move intents to Shared/, dual-target membership (still AppIntent)
    |
    +-- Commit 2: add NowLiveActivityManager.refreshLiveActivity() hook   [after 1]
    |       |
    |       +-- Commit 3: CheckInIntent → LiveActivityIntent + in-process refresh  [after 2]
    |       +-- Commit 4: SnoozeIntent  → LiveActivityIntent + in-process refresh  [after 2]
    |               |
    |               +-- Commit 5: remove Darwin observer + constant   [after 3 AND 4]
```

Commits 3 and 4 are independent of each other after Commit 2 and can be parallelized. Commit 5 must
land only after both 3 and 4 stop posting the ping.

---

## Open question for 3Sauce before implementation

- **Commit 1 is a pure file-move + project-file membership change.** It needs you (or a careful Xcode
  step) to confirm dual-target membership in the IDE, since `.pbxproj` synchronized-group edits are
  fiddly. Are you OK doing that confirmation step manually when we reach Commit 1, or want me to make
  the `.pbxproj` edit and have you verify membership in Xcode afterward?
