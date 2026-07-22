# WilgoTests Cleanup — Design

## Metadata

- **Author:** Claude (with 3Sauce)
- **Date:** 2026-07-22
- **Tracking:** https://app.notion.com/p/clean-up-tests-3904b58e32c38021a045ef05dd44318a?source=copy_link
- **Commit tag:** `#test #cleanup`
- **PRD:** N/A — internal test-infrastructure cleanup, no product behavior change.
- **Delivery:** One branch, one PR, staged commits.

## Goal

Make `WilgoTests/` navigable, DRY, and structurally aligned with the source tree — **without changing what any test asserts**. Every test that passes today must pass identically afterward. This is a behavior-preserving refactor of test infrastructure, not a rewrite.

## Key enabling fact

The Xcode project uses `fileSystemSynchronized` (folder-reference) groups. File moves, renames, and deletions are picked up automatically — **no `.pbxproj` edits required**. This is what makes broad reorganization safe.

## Guiding principles

1. **Behavior-preserving.** No assertion changes. If a shared helper's semantics differ even slightly from what a call site relied on, that call site keeps its own bespoke helper rather than being forced into the shared one.
2. **Mirror source by directory, not exact file.** Some subjects live in catch-all source files (`WilgoApp.swift`, `SettingsView.swift`). Tests are placed in a folder mirroring the *directory* their subject lives in, not the exact file.
3. **Consolidate by judgment.** Merge multiple test files when they clearly test the same subject; keep a folder of multiple files when the subjects are genuinely distinct. No dogmatic one-file-per-source rule.

## Source tree (mirror target)

Top level of `WilgoTests/` mirrors the three source roots:

- `Shared/` → `Shared/Models`, `Shared/Scheduling`, `Shared/Widget`, plus `AppSettings`
- `Wilgo/` → `Wilgo/Features/{Commitments, LiveUpdates, PositivityToken, Settings, Stage, Tags, ...}`
- `WidgetExtension/` → widget/live-activity tests (if any test the extension directly)

## Stages

### Stage 1 — Organization, naming, dead code

**1a. Delete dead code**
- Delete `Commitment/CommitmentAndSlot.swift` (100% commented out).

**1b. Rename non-`*Tests.swift` files**
- `Cycle.swift` → `CyclePeriodMathTests.swift` (matches its `CyclePeriodMathTests` enum)
- `Scheduling/Resolve.swift` → `TimeResolveTests.swift` (matches its `TimeResolveTests` struct)

**1c. Restructure to mirror source directories**
Reorganize the current ad-hoc taxonomy (`Commitment/`, `Slot/`, `Cycle/`, `Notifications/`, `Tag/`, ...) into a source-mirroring layout. Each test file is placed under the folder mirroring the directory of the source it tests. Mapping is grounded by locating the subject symbol's defining source file. Where a subject lives in a catch-all source file, mirror by directory (e.g. scheduler tests → `Wilgo/Features/LiveUpdates` or the directory where the scheduler is defined).

The exact per-file placement table is produced during execution (each placement verified by `grep` for the subject's defining file), not pre-frozen here, because several subjects resolve to broad files and the right home is a judgment call best made against live grep results. Placement decisions are recorded in the PR description.

**1d. Remove now-empty folders** (e.g. `Models/` after its single file moves).

### Stage 2 — Shared date/time helpers

Add `TestHelpers/TestDates.swift`:

```swift
func testDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date
func timeOfDay(hour: Int, minute: Int = 0) -> Date   // the y2000 "time-only" convention
```

Named `testDate` (not `date`) to avoid confusion with `Foundation.Date` and clarify intent. Replace the ~20 private `date(...)` / `timeOfDay(...)` copies across the suite with calls to these. Purely mechanical; verified by a green run.

### Stage 3 — Shared model builders

Add `TestHelpers/TestModelBuilders.swift` with a flexible builder covering the common shape:

```swift
@MainActor func makeCommitment(
    in ctx: ModelContext,
    title: String = "Test",
    slots: [Slot] = [],
    targetCount: Int = 1,
    targetMode: TargetMode = .on,
    cycleKind: CycleKind = .daily,
    continueAfterGoalMet: Bool = false
) -> Commitment

@MainActor func makeSlot(startHour: Int, endHour: Int, maxCheckIns: Int? = nil) -> Slot
```

Adoption is **opt-in per file**: files whose local helper matches this signature switch over. The genuine outliers (slot-tuple sugar `[(start, end, maxCheckIns)]`, `checkInCount`, `encouragements`, etc.) keep their bespoke helpers. The shared builder will **not** be contorted to absorb every variant — a god-builder would be worse than the duplication.

### Stage 4 — Coverage audit (report only)

Cross-reference source files under `Wilgo/`, `Shared/`, `WidgetExtension/` against the reorganized test suite. Produce a markdown report (`docs/superpowers/specs/2026-07-22-wilgotests-coverage-report.md`) of source areas with no apparent test coverage, ranked by apparent importance. Also flag catch-all source files (e.g. `WilgoApp.swift`, `SettingsView.swift`) that mix many testable subjects and would benefit from future splitting. **No new tests are written** — 3Sauce reviews the report and decides.

## Commit plan

Each commit builds and keeps the relevant tests green. Full suite runs on iPhone 17 (iOS 26.4, UDID `4492FF84-2E83-4350-8008-B87DE7AE2588`) at the end via `./test-with-cleanup.sh`.

1. **Delete dead file** (1a) — trivial, isolated.
2. **Rename non-standard files** (1b) — no logic change.
3. **Restructure into source-mirroring folders** (1c, 1d) — moves + consolidations. May be split into sub-commits per top-level area (Shared vs Features) if the diff is large. Test logic unchanged; only file locations and, where consolidated, which file a suite lives in.
4. **Shared date/time helpers** (Stage 2) — add helper file + mechanical replacements.
5. **Shared model builders** (Stage 3) — add builder file + opt-in adoption.
6. **Coverage report** (Stage 4) — docs only.

Dependencies: 1→2→3 are sequential (each operates on the tree the previous left). 4 and 5 depend on 3 (so replacements land in final locations). 6 depends on 3 (audits final structure).

Every commit footer includes:

```
#test #cleanup
tracking: https://app.notion.com/p/clean-up-tests-3904b58e32c38021a045ef05dd44318a?source=copy_link
```

## Manual verification

None required beyond automated tests — no migrations, no on-device behavior. The full suite passing on iPhone 17 is the acceptance gate.

## Alternatives considered

- **One god-builder for `makeCommitment`** — rejected. The 20 copies genuinely diverge; a single signature covering all would be wide and unreadable, harming clarity more than the duplication does.
- **Strict one-file-per-source-file mirror** — rejected. Several subjects live in catch-all source files; forcing exact-file mirroring produces awkward folders. Directory-level mirroring is the pragmatic choice.
- **Renaming shared `testDate` back to `date`** — rejected. `date` confuses with `Foundation.Date`; `testDate` reads clearly at call sites.
