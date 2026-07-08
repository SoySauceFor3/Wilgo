# Standalone probe: does `activity.update()` mutate a *pending* Live Activity?

- **Date:** 2026-07-08
- **Author:** Claude (for 3Sauce)
- **Related:** `Shared/Widget/LiveActivityRefresher.swift` (`updateStartedCards` → `activity.update(content(for:))`), `#scheduledLA`
- **Status:** RESOLVED — probe run on-device 2026-07-08

## Result (2026-07-08)

**`activity.update()` silently no-ops on a `.pending` scheduled card.**

Ran the probe on device. The scheduled card fired ~90s after launch showing
**PROBE-BEFORE** — i.e. the `update()` call made while the card was still `.pending`
did NOT change the content that eventually displayed. `update()` returned without
throwing (as expected — it is non-throwing in this SDK), giving no failure signal,
yet the content change was lost.

**Implication for production:** `LiveActivityRefresher.updateStartedCards` cannot
rely on `.update()` to edit a card that has not yet started. Content changes that
land while a scheduled card is `.pending` are dropped. A card must be re-created
(end + re-request with the new content) rather than updated while pending — or the
update must be deferred until the card is `.active`. This needs a follow-up fix in
the reconcile logic.

## Question being answered

When a scheduled Live Activity is still `.pending` (the system is holding it to
start at a future `start:` date), does `activity.update(content:)` change the
content that eventually displays when the card fires — or does it silently no-op?

The production `LiveActivityRefresher.updateStartedCards` calls `.update()` on
seated cards. If `.update()` no-ops on `.pending` cards, edits made before a
scheduled card starts would be silently lost. This probe convicts or clears that.

## Approach

A **standalone, self-contained probe** that runs once right after app start, with
**no UI**. In the probe build, **all** normal `NowLiveActivityManager` reconcile
work is suppressed so nothing else touches ActivityKit — the single probe card is
the only Live Activity in play, and it survives untouched until its scheduled
start time so it can be eye-inspected.

The whole proof is a sequence of `os.Logger` lines plus one manual eye-check of
the card that appears ~90s after launch.

### The probe (`Shared/Widget/PendingUpdateProbe.swift`)

`enum PendingUpdateProbe { @MainActor static func run() async }`:

1. Build a `NowAttributes.ContentState` with
   `commitmentTitle = "PROBE-BEFORE HH:mm:ss"`, `windowStart ≈ now + 90s`,
   `windowEnd ≈ now + 1h`, throwaway UUIDs, other fields nil/valid.
2. `Activity.request(..., style: .standard, alertConfiguration:, start: windowStart)`
   — a **scheduled** request → card is created `.pending`. Log the returned id and
   `activityState` (expect `.pending`).
3. `await Task.sleep` ~5s (still before `windowStart`, so still `.pending`);
   re-log `activityState` to confirm still pending.
4. Build a second `ContentState`, identical **except**
   `commitmentTitle = "PROBE-AFTER HH:mm:ss"`.
5. `await activity.update(ActivityContent(state: after, staleDate: nil))` inside
   `do/catch`. Log `"update() returned (no throw)"` or the caught error, then
   re-log `activityState`.
6. Log the id and a reminder to watch for the card at `windowStart`.

### Suppressing all other LA work

`NowLiveActivityManager.apply()` is the single choke point every reconcile path
routes through (`workAndScheduleNextBGTask`, the BGTask handler). In the probe
build its body short-circuits to a logged no-op and returns, so no reconcile ever
runs and the probe card is never ended as an orphan.

### Toggle

A custom active-compilation-condition `PENDING_UPDATE_PROBE`, added to the **app
target's Debug config only** (`SWIFT_ACTIVE_COMPILATION_CONDITIONS`, line ~668 of
`project.pbxproj`). Normal debug builds keep real LA behavior; flip the flag only
when probing. Guarded call site: `AppRootView` gets `.task { await PendingUpdateProbe.run() }`
under `#if PENDING_UPDATE_PROBE`.

## Manual verification (the payoff)

1. Enable `PENDING_UPDATE_PROBE`, build & run on device (iPhone 17 sim can host the
   card too, but on-device is the faithful check).
2. Read the log (subsystem `wilgo`, category `LiveActivityProbe`): confirm the card
   was requested `.pending`, still `.pending` at update time, and whether `update()`
   threw.
3. ~90s after launch the scheduled card appears.
   - Reads **PROBE-AFTER** → `update()` on pending **works**.
   - Reads **PROBE-BEFORE** → `update()` on pending **silently no-ops**.

## Why this design

- **No UI** (per 3Sauce): a `.task` on the root view fires once, no button plumbing.
- **Suppress all LA work** (per 3Sauce): isolates the experiment to a single card so
  the production refresher can't end the orphan before inspection.
- **Timestamped title delta** (per 3Sauce): unmistakable on the card and in the log.
- **Custom flag, not plain DEBUG** (per 3Sauce): keeps normal debug LA behavior intact.

## Cleanup

One dedicated file + one `.task` line + one `#if` block in `apply()` + one build-setting
token. Delete the file and revert three small edits to fully remove.

## Not doing (YAGNI)

- No XCTest vehicle — ActivityKit refuses to seat activities headlessly, so it would
  prove nothing.
- No DB writes / no real commitments — throwaway UUIDs keep dogfood state untouched.
