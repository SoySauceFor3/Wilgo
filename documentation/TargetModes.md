# Target Modes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**PRD:** [reconcile grace and target disable 050726](https://www.notion.so/reconcile-grace-and-target-disable-050726-3594b58e32c380e587f6f82056e7bd4b)  
**Tracking:** [refactor target disable grace](https://www.notion.so/refactor-target-disable-grace-3574b58e32c38071b420e3641a225d12)  
**Tag:** `#TargetModes`  
**Date:** 2026-05-07

---

## Context

Wilgo currently has two overlapping target-pressure concepts:

- `Target.isEnabled == false`: a durable target-disabled state. Stage uses `targetDisabledStatus(now:)`, reports do not consume PT, and target math is suppressed.
- `Commitment.gracePeriods`: historical exemption windows created during add/edit flows. Reports skip punishment/PT, but Stage remains aligned with `Target On` because `stageStatus(now:)` does not read grace.

The PRD reconciles these as three target modes:

- `On`: target counts and all evaluation applies.
- `Inspiration Only until X`: target number remains visible as an inspirational reference; punishment/failure/PT do not apply during the interval. `X` is a cycle start or `forever`.
- `Disabled`: no active target evaluation and no target goal math.

Default Stage behavior for Inspiration Only stays aligned with `On`: if the inspiration number is reached, Stage may still enter `.metGoal` and hide remaining cycle slots. A future reminder preference may later let users choose whether goal completion mutes reminders.

---

## Architecture Summary

Move target mode into `Target` itself. Replace `Target.isEnabled` with a `TargetMode` enum that captures all three user-facing states:

```swift
enum TargetMode: Codable, Hashable {
    case on
    case inspirationOnly(start: Date, until: Date?)
    case disabled
}
```

`start` is stored so delayed FinishedCycleReport generation can correctly classify cycles that were Inspiration Only before `until`. `until == nil` means forever. Live behavior reads `target.effectiveMode(on:)`, so expired finite Inspiration Only behaves as `On` even before storage cleanup runs.

Add a pre-commit to improve FinishedCycleReport lifecycle: do not advance the report watermark before the sheet is actually consumed. Add a finalization callback that advances the watermark and then normalizes expired finite `TargetMode.inspirationOnly` values to `.on`. Report correctness must not depend on normalization; normalization is storage cleanup after the report has used the stored interval.

---

## Design Decisions

### Store target mode on `Target`

**Decision:** `Target` becomes:

```swift
struct Target: Codable, Hashable {
    var count: Int
    var mode: TargetMode = .on
}
```

**Why not keep `isEnabled` plus a separate inspiration list?** The product model is exactly three target modes. Storing them in one enum makes the model easier to reason about and avoids spreading mode semantics across `Target.isEnabled` and `Commitment.gracePeriods`.

**Risk:** This touches more call sites than wrapping the existing fields. Mitigation: keep compatibility helpers like `target.isEnabled` during the commit chain if useful, then migrate business logic to `effectiveMode`.

### Store `start` and `until` for Inspiration Only

**Decision:** Use `case inspirationOnly(start: Date, until: Date?)`.

**Why not only store `until`?** A delayed report can cover multiple finished cycles. If the user set Inspiration Only from Dec 1 until Jan 1 and opens the app on Mar 1, the report should classify Dec as Inspiration Only and Jan/Feb as On. `until` alone works only if the report window starts when Inspiration Only started. `start` makes the interval explicit and keeps report classification independent of caller promises.

**Cost:** One extra date and slightly more save logic.

**Benefit:** Robust report classification, simpler than preserving a full period list.

### Effective mode and normalization are separate

**Decision:** Live code should use derived behavior:

```swift
target.effectiveMode(on: psychDay)
```

Storage cleanup should happen only after FinishedCycleReport has consumed the report window.

**Why not normalize on app activation or form open?** If storage is normalized to `.on` before report generation, the stored `start/until` interval is lost and delayed reports can no longer classify Inspiration Only cycles correctly.

### FinishedCycleReport finalization owns normalization timing

**Decision:** Add an `onFinished` callback to `FinishedCycleReportView`. Only after the report flow is consumed should Wilgo:

1. Normalize finite `inspirationOnly` modes whose `until <= request.endPsychDay` to `.on`.
2. Save the model context.
3. Advance the report watermark to `request.endPsychDay`.

**Why improve FinishedCycleReport first?** Current `FinishedCycleReportModifier.checkAndShow()` advances the watermark before knowing whether the user saw or completed the report. Target-mode normalization needs a clear "report window was consumed" moment.

### Inspiration Only follows Target On in Stage

**Decision:** `stageStatus(now:)` should route `.on` and `.inspirationOnly` through the existing target-on branch. `.disabled` routes through `targetDisabledStatus(now:)`.

**Why not route Inspiration Only to disabled scheduling?** Product direction is to keep current behavior until a future "mute reminders after goal reached" preference exists. Stage scheduling is not punishment/PT evaluation.

---

## Major Model Changes

| Entity                                                                             | Change                                                                                                                                             |
| ---------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Shared/Models/TargetMode.swift`                                                   | New target-mode enum and helper methods.                                                                                                           |
| `Shared/Models/GracePeriod.swift`                                                  | Legacy grace-period model removed after report and form flows no longer use grace-period storage.                                                  |
| `Shared/Models/Commitment.swift`                                                   | Replace `gracePeriods` and `Target.isEnabled` branching with `Target.mode` / `effectiveMode`. Add report classification and normalization helpers. |
| `Wilgo/Features/Commitments/FinishedCycleReport/FinishedCycleReportModifier.swift` | Delay watermark advancement until report finalization.                                                                                             |
| `Wilgo/Features/Commitments/FinishedCycleReport/FinishedCycleReportView.swift`     | Add `onFinished` callback.                                                                                                                         |
| `Wilgo/Features/Commitments/Form/CommitmentFormDraft.swift`                        | Store and save `Target.mode`.                                                                                                                      |
| `Wilgo/Features/Commitments/Form/CommitmentFormFields.swift`                       | Replace "Enable target" toggle with target mode picker.                                                                                            |
| `Wilgo/Features/Commitments/Form/AddCommitmentView.swift`                          | Save explicit target modes directly; ask current-cycle question only when saving `On`.                                                             |
| `Wilgo/Features/Commitments/Form/EditCommitmentView.swift`                         | Same save behavior as Add, with rule-change detection preserved.                                                                                   |
| Finished-cycle report files                                                        | Replace report booleans with resolved `effectiveTargetMode`; keep PT exclusion behavior.                                                           |
| Tests                                                                              | Add FinishedCycleReport lifecycle, target-mode model, form-draft, Stage, and report regression coverage.                                           |

---

## Commit Plan

All commits should end with:

```text
#TargetModes

tracking: https://www.notion.so/refactor-target-disable-grace-3574b58e32c38071b420e3641a225d12
```

Run focused tests first. Run broader verification only after focused tests pass:

```bash
./test-with-cleanup.sh
```

The full suite may still include the documented pre-existing failure `CommitmentStageSnoozeTests/stageStatus_snoozeDoesNotAffectFutureOccurrence()`. Do not attribute that failure to this work unless fresh evidence shows it changed.

---

### Phase 0 — FinishedCycleReport finalization flow

The goal of this phase is to create a reliable "report window consumed" hook before target-mode normalization depends on it.

#### Commit 0 — refactor: finalize finished-cycle report after sheet completion

**Files:**

- Modify: `Wilgo/Features/Commitments/FinishedCycleReport/FinishedCycleReportModifier.swift`
- Modify: `Wilgo/Features/Commitments/FinishedCycleReport/FinishedCycleReportView.swift`

- [ ] **Step 1: Move watermark advancement out of `checkAndShow()`**

In `FinishedCycleReportModifier.checkAndShow()`, replace:

```swift
advanceWatermark(to: request.endPsychDay)
reportRequest = request
```

with:

```swift
reportRequest = request
```

Keep `advanceWatermark(to:)` in the file for the finalization callback.

- [ ] **Step 2: Add report finalization helper**

In `FinishedCycleReportModifier`, add:

```swift
private func finalizeReport(_ request: FinishedCycleReportRequest) {
    advanceWatermark(to: request.endPsychDay)
    reportRequest = nil
    shouldShowReport = false
}
```

Target-mode normalization will be added to this helper in a later commit after the model API exists.

- [ ] **Step 3: Pass finalization callback into the sheet**

In the `.fullScreenCover`, replace:

```swift
FinishedCycleReportView(request: request)
```

with:

```swift
FinishedCycleReportView(
    request: request,
    onFinished: { finalizeReport(request) }
)
```

- [ ] **Step 4: Add callback to report view**

In `FinishedCycleReportView.swift`, change:

```swift
struct FinishedCycleReportView: View {
    let request: FinishedCycleReportRequest
    @Environment(\.dismiss) private var dismiss
```

to:

```swift
struct FinishedCycleReportView: View {
    let request: FinishedCycleReportRequest
    let onFinished: () -> Void
    @Environment(\.dismiss) private var dismiss
```

Update completion paths:

```swift
CheckInSummaryStep(
    request: request,
    onNext: { preTokenReport in
        preTokenReportForTokenStep = preTokenReport
        showTokenStep = true
    },
    onEmptyReport: {
        onFinished()
        dismiss()
    }
)
```

and:

```swift
PositivityTokenStep(
    preTokenReport: preTokenReportForTokenStep,
    onDone: {
        onFinished()
        dismiss()
    }
)
```

Update preview:

```swift
FinishedCycleReportView(request: request, onFinished: {})
```

- [ ] **Step 5: Manual verification**

On iPhone 17 simulator:

- Trigger a finished-cycle report.
- Verify the report appears.
- Complete the report.
- Relaunch the app.
- Verify the same report does not reappear after completion.

- [ ] **Step 6: Build**

Run:

```bash
xcodebuild build -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Wilgo/Features/Commitments/FinishedCycleReport/FinishedCycleReportModifier.swift Wilgo/Features/Commitments/FinishedCycleReport/FinishedCycleReportView.swift
git commit -m "refactor: finalize finished cycle reports after completion

#TargetModes

tracking: https://www.notion.so/refactor-target-disable-grace-3574b58e32c38071b420e3641a225d12"
```

---

### Phase 1 — TargetMode model

The goal of this phase is to move target state into a single enum and define behavior/report helpers.

#### Commit 1 — refactor: replace target enabled flag with TargetMode

**Files:**

- Create: `Shared/Models/TargetMode.swift`
- Modify: `Shared/Models/Commitment.swift`
- Create: `WilgoTests/Commitment/TargetModeTests.swift`

- [ ] **Step 1: Write failing model tests**

Create `WilgoTests/Commitment/TargetModeTests.swift`:

```swift
import Foundation
import Testing
@testable import Wilgo

@Suite("TargetMode", .serialized)
struct TargetModeTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps)!
    }

    @Test("on is effective on")
    func onIsEffectiveOn() throws {
        #expect(try TargetMode.on.effectiveMode(on: date(2026, 3, 1)) == .on)
    }

    @Test("disabled is effective disabled")
    func disabledIsEffectiveDisabled() throws {
        #expect(try TargetMode.disabled.effectiveMode(on: date(2026, 3, 1)) == .disabled)
    }

    @Test("finite inspiration only is effective before until and on at until")
    func finiteInspirationOnlyExpires() throws {
        let mode = TargetMode.inspirationOnly(
            start: date(2025, 12, 1),
            until: date(2026, 1, 1)
        )

        #expect(try mode.effectiveMode(on: date(2025, 12, 15)) == mode)
        #expect(try mode.effectiveMode(on: date(2026, 1, 1)) == .on)
        #expect(try mode.effectiveMode(on: date(2026, 3, 1)) == .on)
    }

    @Test("inspiration only before start throws")
    func inspirationOnlyBeforeStartThrows() {
        let mode = TargetMode.inspirationOnly(
            start: date(2025, 12, 1),
            until: date(2026, 1, 1)
        )

        do {
            _ = try mode.effectiveMode(on: date(2025, 11, 30))
            Issue.record("Expected effectiveMode before inspiration start to throw")
        } catch TargetModeError.effectiveModeBeforeInspirationStart {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("forever inspiration only stays effective")
    func foreverInspirationOnlyStaysEffective() throws {
        let mode = TargetMode.inspirationOnly(start: date(2025, 12, 1), until: nil)

        #expect(try mode.effectiveMode(on: date(2026, 3, 1)) == mode)
    }

    @Test("finite inspiration only overlaps only its interval")
    func finiteInspirationOnlyOverlapsOnlyItsInterval() {
        let mode = TargetMode.inspirationOnly(
            start: date(2025, 12, 1),
            until: date(2026, 1, 1)
        )

        #expect(!mode.overlapsInspirationOnlyInterval(cycleStart: date(2025, 11, 1), cycleEnd: date(2025, 12, 1)))
        #expect(mode.overlapsInspirationOnlyInterval(cycleStart: date(2025, 12, 1), cycleEnd: date(2026, 1, 1)))
        #expect(!mode.overlapsInspirationOnlyInterval(cycleStart: date(2026, 1, 1), cycleEnd: date(2026, 2, 1)))
    }

    @Test("expired finite inspiration only can normalize to on")
    func expiredFiniteInspirationOnlyNormalizesToOn() {
        let mode = TargetMode.inspirationOnly(
            start: date(2025, 12, 1),
            until: date(2026, 1, 1)
        )

        #expect(mode.normalized(afterReportedThrough: date(2025, 12, 31)) == mode)
        #expect(mode.normalized(afterReportedThrough: date(2026, 1, 1)) == .on)
    }

    @Test("old disabled target decodes as disabled mode")
    func oldDisabledTargetDecodesAsDisabledMode() throws {
        let data = #"{"count":3,"isEnabled":false}"#.data(using: .utf8)!

        let target = try JSONDecoder().decode(Target.self, from: data)

        #expect(target.count == 3)
        #expect(target.mode == .disabled)
    }

    @Test("old target without isEnabled decodes as on")
    func oldTargetWithoutIsEnabledDecodesAsOn() throws {
        let data = #"{"count":3}"#.data(using: .utf8)!

        let target = try JSONDecoder().decode(Target.self, from: data)

        #expect(target.count == 3)
        #expect(target.mode == .on)
    }
}
```

- [ ] **Step 2: Run model tests and verify failure**

Run:

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' -only-testing:WilgoTests/TargetModeTests
```

Expected: build fails because `TargetMode` does not exist.

- [ ] **Step 3: Add `TargetMode` and update `Target`**

Create `Shared/Models/TargetMode.swift`:

```swift
import Foundation

enum TargetMode: Codable, Hashable {
    case on
    case inspirationOnly(start: Date, until: Date?)
    case disabled

    func effectiveMode(on psychDay: Date) throws -> TargetMode {
        switch self {
        case .on, .disabled:
            return self
        case .inspirationOnly(let start, let until):
            if psychDay < start {
                throw TargetModeError.effectiveModeBeforeInspirationStart(
                    psychDay: psychDay,
                    start: start
                )
            }

            if let until, psychDay >= until {
                return .on
            } else {
                return self
            }
        }
    }

    func overlapsInspirationOnlyInterval(cycleStart: Date, cycleEnd: Date) -> Bool {
        guard case .inspirationOnly(let start, let until) = self else { return false }
        let end = until ?? Date.distantFuture
        return start < cycleEnd && end > cycleStart
    }

    func normalized(afterReportedThrough reportedEndPsychDay: Date) -> TargetMode {
        switch self {
        case .on, .disabled:
            return self
        case .inspirationOnly(_, let until):
            if let until, until <= reportedEndPsychDay {
                return .on
            } else {
                return self
            }
        }
    }
}

enum TargetModeError: Error, Equatable {
    case effectiveModeBeforeInspirationStart(psychDay: Date, start: Date)
}

```

In `Shared/Models/Commitment.swift`, change:

```swift
struct Target: Codable, Hashable {
    var count: Int
    var mode: TargetMode = .on
}
```

Add a compatibility computed property during migration:

```swift
extension Target {
    var isEnabled: Bool {
        get { mode != .disabled }
        set { mode = newValue ? .on : .disabled }
    }
}
```

Keep `var gracePeriods: [GracePeriod] = []` in `Commitment` during this commit so old report code still compiles. Remove it in Phase 2 after report classification moves to `TargetMode`.

Add commitment helpers:

```swift
func effectiveTargetMode(on psychDay: Date = Time.startOfDay(for: Time.now())) throws -> TargetMode {
    try target.mode.effectiveMode(on: psychDay)
}

func hasInspirationOnlyOverlap(cycleStart: Date, cycleEnd: Date) -> Bool {
    target.mode.overlapsInspirationOnlyInterval(cycleStart: cycleStart, cycleEnd: cycleEnd)
}

func normalizeTargetMode(afterReportedThrough reportedEndPsychDay: Date) {
    target.mode = target.mode.normalized(afterReportedThrough: reportedEndPsychDay)
}
```

Do not migrate form cycle-boundary behavior in this commit. Later form commits must re-snap
`inspirationOnly(start:until:)` to valid cycle starts whenever the user changes the commitment
cycle but keeps Inspiration Only.

- [ ] **Step 4: Run model tests and verify pass**

Run:

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' -only-testing:WilgoTests/TargetModeTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Shared/Models/TargetMode.swift Shared/Models/Commitment.swift WilgoTests/Commitment/TargetModeTests.swift
git commit -m "refactor: model target modes as enum

#TargetModes

tracking: https://www.notion.so/refactor-target-disable-grace-3574b58e32c38071b420e3641a225d12"
```

---

### Phase 2 — Target API, reports, normalization, and grace-storage removal

The goal of this phase is to harden the target-mode API before report logic uses it, make reports classify each finished cycle from `TargetMode` intervals, normalize expired finite modes only after report completion, and remove old `GracePeriod` storage in a separate cleanup commit.

#### Commit 2 — refactor: harden target mode API

**Files:**

- Modify: `Shared/Models/TargetMode.swift`
- Modify: `Shared/Models/Commitment.swift`
- Modify: `WilgoTests/Commitment/TargetModeTests.swift`

- [ ] **Step 1: Add range effective-mode and configured-mode tests**

In `TargetModeTests.swift`, add:

```swift
@Test("finite inspiration only effective range overlaps only its interval")
func finiteInspirationOnlyEffectiveRangeOverlapsOnlyItsInterval() throws {
    let mode = TargetMode.inspirationOnly(
        start: date(2025, 12, 1),
        until: date(2026, 1, 1)
    )

    #expect(try mode.effectiveMode(from: date(2025, 11, 1), to: date(2025, 12, 1)) == .on)
    #expect(try mode.effectiveMode(from: date(2025, 12, 1), to: date(2026, 1, 1)) == mode)
    #expect(try mode.effectiveMode(from: date(2026, 1, 1), to: date(2026, 2, 1)) == .on)
}

@Test("invalid effective range throws")
func invalidEffectiveRangeThrows() {
    do {
        _ = try TargetMode.on.effectiveMode(from: date(2026, 1, 1), to: date(2026, 1, 1))
        Issue.record("Expected invalid range to throw")
    } catch TargetModeError.invalidEffectiveModeRange {
        // expected
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test("configured mode exposes stored mode explicitly")
func configuredModeExposesStoredMode() {
    var target = Target(count: 3, mode: .disabled)

    #expect(target.configuredMode == .disabled)

    target.setConfiguredMode(.on)

    #expect(target.configuredMode == .on)
}
```

Update existing decode assertions from:

```swift
#expect(target.mode == .disabled)
#expect(target.mode == .on)
```

to:

```swift
#expect(target.configuredMode == .disabled)
#expect(target.configuredMode == .on)
```

- [ ] **Step 2: Run model tests and verify failure**

Run:

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' -only-testing:WilgoTests/TargetModeTests
```

Expected: build fails because range effective-mode and configured-mode APIs do not exist.

- [ ] **Step 3: Add range effective-mode API**

In `TargetMode.swift`, add:

```swift
func effectiveMode(from startPsychDay: Date, to endPsychDay: Date) throws -> TargetMode {
    guard startPsychDay < endPsychDay else {
        throw TargetModeError.invalidEffectiveModeRange(
            startPsychDay: startPsychDay,
            endPsychDay: endPsychDay
        )
    }

    switch self {
    case .on, .disabled:
        return self
    case .inspirationOnly(let start, let until):
        let end = until ?? Date.distantFuture
        if start < endPsychDay && end > startPsychDay {
            return self
        } else {
            return .on
        }
    }
}
```

and extend the error enum:

```swift
enum TargetModeError: Error, Equatable {
    case effectiveModeBeforeInspirationStart(psychDay: Date, start: Date)
    case invalidEffectiveModeRange(startPsychDay: Date, endPsychDay: Date)
}
```

Keep `overlapsInspirationOnlyInterval(cycleStart:cycleEnd:)` only if an existing test still needs it during this commit; later report code should use `effectiveMode(from:to:)`.

- [ ] **Step 4: Make stored mode private and add explicit configured/effective APIs**

In `Target`, change:

```swift
var mode: TargetMode = .on
```

to:

```swift
private var mode: TargetMode = .on
```

Add:

```swift
extension Target {
    var configuredMode: TargetMode { mode }

    func effectiveMode(on psychDay: Date) throws -> TargetMode {
        try mode.effectiveMode(on: psychDay)
    }

    func effectiveMode(from startPsychDay: Date, to endPsychDay: Date) throws -> TargetMode {
        try mode.effectiveMode(from: startPsychDay, to: endPsychDay)
    }

    mutating func setConfiguredMode(_ mode: TargetMode) {
        self.mode = mode
    }

    mutating func normalizeMode(afterReportedThrough reportedEndPsychDay: Date) {
        mode = mode.normalized(afterReportedThrough: reportedEndPsychDay)
    }
}
```

Keep `isEnabled` as a compatibility shim, but implement it through private storage:

```swift
extension Target {
    var isEnabled: Bool {
        get { mode != .disabled }
        set { mode = newValue ? .on : .disabled }
    }
}
```

Remove `hasInspirationOnlyOverlap(cycleStart:cycleEnd:)`; report classification should use the range effective-mode helper.

- [ ] **Step 5: Run model tests and build**

Run:

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' -only-testing:WilgoTests/TargetModeTests
xcodebuild build -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588'
```

Expected: PASS and BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Shared/Models/TargetMode.swift Shared/Models/Commitment.swift WilgoTests/Commitment/TargetModeTests.swift
git commit -m "refactor: harden target mode API

#TargetModes

tracking: https://www.notion.so/refactor-target-disable-grace-3574b58e32c38071b420e3641a225d12"
```

#### Commit 3 — feat: report inspiration-only cycles from effective target mode

**Files:**

- Modify: `Wilgo/Features/Commitments/FinishedCycleReport/Models.swift`
- Modify: `Wilgo/Features/Commitments/FinishedCycleReport/PreTokenReportBuilder.swift`
- Modify: `Wilgo/Features/Commitments/FinishedCycleReport/PositivityTokenCompensator.swift`
- Modify: `Wilgo/Features/Commitments/FinishedCycleReport/CheckInSummaryPage.swift`
- Modify: `Wilgo/Features/Commitments/FinishedCycleReport/PositivityTokenPage.swift`
- Modify: `WilgoTests/FinishedCycleReport/FinishedCycleReportBuilderTests.swift`

- [ ] **Step 1: Add delayed report test**

In `FinishedCycleReportBuilderTests.swift`, add:

```swift
@Test("inspiration only until Jan 1: delayed report marks Dec only")
@MainActor
func inspirationOnlyDelayedReportMarksOnlyOverlappingCycles() throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    let anchor = date(year: 2025, month: 12, day: 1)
    let commitment = Commitment(
        title: "Run",
        cycle: Cycle(kind: .monthly, referencePsychDay: anchor),
        slots: [],
        target: Target(
            count: 3,
            mode: .inspirationOnly(
                start: date(year: 2025, month: 12, day: 1),
                until: date(year: 2026, month: 1, day: 1)
            )
        )
    )
    ctx.insert(commitment)

    let report = PreTokenReportBuilder.build(
        commitments: [commitment],
        startPsychDay: date(year: 2025, month: 12, day: 1),
        endPsychDay: date(year: 2026, month: 3, day: 1)
    )

    let cycles = try #require(report.first?.cycles)
    #expect(cycles.count == 3)
    #expect(cycles[0].effectiveTargetMode == .inspirationOnly(
        start: date(year: 2025, month: 12, day: 1),
        until: date(year: 2026, month: 1, day: 1)
    ))
    #expect(cycles[1].effectiveTargetMode == .on)
    #expect(cycles[2].effectiveTargetMode == .on)
}
```

- [ ] **Step 2: Run report tests and verify failure**

Run:

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' -only-testing:WilgoTests/FinishedCycleReportBuilderTests
```

Expected: build fails because report fields still use `isGrace` and `isTargetEnabled`.

- [ ] **Step 3: Replace report booleans with effective target mode**

In `Models.swift`, replace:

```swift
/// True when this cycle is covered by a grace period — no penalty and no PT tokens applied.
let isGrace: Bool
/// True when the commitment's target was enabled for this cycle.
/// When false, the cycle is informational only — no pass/fail and no PT consumed.
let isTargetEnabled: Bool
```

with:

```swift
/// Effective target mode for this finished cycle. This is resolved from the
/// stored `TargetMode` and the cycle date range, so non-normalized expired
/// Inspiration Only modes still report later cycles as `.on`.
let effectiveTargetMode: TargetMode
```

Do not pass raw `commitment.target.configuredMode` into `CycleReport`. Report rows must store
the resolved value from `effectiveTargetMode(from:to:)`.

- [ ] **Step 4: Update PreTokenReportBuilder**

Replace:

```swift
let isGrace = commitment.gracePeriods.contains {
    $0.overlaps(cycleStart: cycleStart, cycleEnd: cycleEnd)
}
```

with:

```swift
let effectiveTargetMode = try commitment.effectiveTargetMode(
    from: cycleStart,
    to: cycleEnd
)
```

Because `cyclesForCommitment` now calls a throwing helper, make `build` skip cycles that cannot be
classified and log the error:

```swift
do {
    let effectiveTargetMode = try commitment.effectiveTargetMode(from: cycleStart, to: cycleEnd)
    // append CycleDraft
} catch {
    print("[FCR] failed to classify target mode for \(commitment.title): \(error)")
}
```

Pass `effectiveTargetMode` into `CycleDraft` and `CycleReport`.

- [ ] **Step 5: Update PT filters and report UI copy**

In `PositivityTokenCompensator.swift`, replace:

```swift
guard !cycle.isGrace, cycle.isTargetEnabled else { return nil }
```

with:

```swift
guard case .on = cycle.effectiveTargetMode else { return nil }
```

In `CheckInSummaryPage.swift` and `PositivityTokenPage.swift`, use:

```swift
Text("\(cycle.actualCheckIns)/\(cycle.targetCheckIns) check-ins · inspiration only")
```

- [ ] **Step 6: Run focused report tests**

Run:

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' -only-testing:WilgoTests/FinishedCycleReportBuilderTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Wilgo/Features/Commitments/FinishedCycleReport WilgoTests/FinishedCycleReport/FinishedCycleReportBuilderTests.swift
git commit -m "feat: report inspiration-only target modes

#TargetModes

tracking: https://www.notion.so/refactor-target-disable-grace-3574b58e32c38071b420e3641a225d12"
```

#### Commit 4 — refactor: normalize target modes after report finalization

**Files:**

- Modify: `Wilgo/Features/Commitments/FinishedCycleReport/FinishedCycleReportModifier.swift`
- Modify: `WilgoTests/FinishedCycleReport/FinishedCycleReportPresentationStateTests.swift`

- [ ] **Step 1: Add normalization helper test**

In `FinishedCycleReportPresentationStateTests.swift`, add a test for a pure helper that normalizes
expired finite Inspiration Only modes after the consumed report window:

```swift
@Test("normalization turns expired finite inspiration only back on")
func normalizationTurnsExpiredFiniteInspirationOnlyBackOn() {
    let until = date(year: 2026, month: 1, day: 1)
    let commitment = Commitment(
        title: "Run",
        cycle: Cycle(kind: .monthly, referencePsychDay: date(year: 2025, month: 12, day: 1)),
        slots: [],
        target: Target(
            count: 3,
            mode: .inspirationOnly(
                start: date(year: 2025, month: 12, day: 1),
                until: until
            )
        )
    )

    normalizeExpiredTargetModes(
        in: [commitment],
        afterReportedThrough: date(year: 2026, month: 3, day: 1)
    )

    #expect(commitment.target.configuredMode == .on)
}
```

- [ ] **Step 2: Add non-expired normalization test**

In `FinishedCycleReportPresentationStateTests.swift`, add:

```swift
@Test("normalization keeps active finite inspiration only")
func normalizationKeepsActiveFiniteInspirationOnly() {
    let mode = TargetMode.inspirationOnly(
        start: date(year: 2026, month: 1, day: 1),
        until: date(year: 2026, month: 4, day: 1)
    )
    let commitment = Commitment(
        title: "Run",
        cycle: Cycle(kind: .monthly, referencePsychDay: date(year: 2026, month: 1, day: 1)),
        slots: [],
        target: Target(count: 3, mode: mode)
    )

    normalizeExpiredTargetModes(
        in: [commitment],
        afterReportedThrough: date(year: 2026, month: 3, day: 1)
    )

    #expect(commitment.target.configuredMode == mode)
}
```

- [ ] **Step 3: Run presentation-state tests and verify failure**

Run:

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' -only-testing:WilgoTests/FinishedCycleReportPresentationStateTests
```

Expected: build fails until `normalizeExpiredTargetModes` exists.

- [ ] **Step 4: Add normalization helper and call it after report finalization**

In `FinishedCycleReportModifier.swift`, add a top-level helper near `advanceWatermark(to:)`:

```swift
func normalizeExpiredTargetModes(
    in commitments: [Commitment],
    afterReportedThrough reportedEndPsychDay: Date
) {
    for commitment in commitments {
        commitment.target.normalizeMode(afterReportedThrough: reportedEndPsychDay)
    }
}
```

In `FinishedCycleReportModifier.finalizeReport(_:)`, advance and close the consumed report first.
Then try to normalize expired finite modes as best-effort cleanup:

```swift
private func finalizeReport(_ request: FinishedCycleReportRequest) {
    presentationState.finalize(request) { psychDay in
        advanceWatermark(to: psychDay)
    }

    do {
        let commitments = try modelContext.fetch(FetchDescriptor<Commitment>())
        normalizeExpiredTargetModes(in: commitments, afterReportedThrough: request.endPsychDay)
        try modelContext.save()
    } catch {
        print("[FCR] target mode normalization failed after report finalization: \(error)")
    }
}
```

If normalization does not happen in time, correctness still holds: delayed report classification uses
the stored `start/until` interval, and effective mode treats expired finite Inspiration Only as On.
The user should not see a duplicate report because cleanup failed.

- [ ] **Step 5: Run focused presentation-state tests**

Run:

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' -only-testing:WilgoTests/FinishedCycleReportPresentationStateTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Wilgo/Features/Commitments/FinishedCycleReport/FinishedCycleReportModifier.swift WilgoTests/FinishedCycleReport/FinishedCycleReportPresentationStateTests.swift
git commit -m "refactor: normalize target modes after report finalization

#TargetModes

tracking: https://www.notion.so/refactor-target-disable-grace-3574b58e32c38071b420e3641a225d12"
```

#### Commit 5 — refactor: remove grace storage

**Files:**

- Modify: `Shared/Models/Commitment.swift`
- Delete: `Shared/Models/GracePeriod.swift`
- Modify: `Wilgo.xcodeproj/project.pbxproj` if target membership still references `GracePeriod.swift`
- Modify tests found by `rg -n "GracePeriod|gracePeriods" WilgoTests Shared Wilgo`

- [ ] **Step 1: Remove grace storage**

After `PreTokenReportBuilder` and report tests use `TargetMode`, remove:

```swift
var gracePeriods: [GracePeriod] = []
```

from `Commitment`, and delete `Shared/Models/GracePeriod.swift`.

- [ ] **Step 2: Remove stale grace-period tests and target membership**

Run:

```bash
rg -n "GracePeriod|gracePeriods" Wilgo Shared WilgoTests WidgetExtension
```

Expected: remove or rename all source/test references to the old storage model. If
`Wilgo.xcodeproj/project.pbxproj` references `GracePeriod.swift`, remove that target membership entry.

- [ ] **Step 3: Run focused report tests**

Run:

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' -only-testing:WilgoTests/FinishedCycleReportBuilderTests
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Shared/Models/Commitment.swift Shared/Models/GracePeriod.swift Wilgo.xcodeproj/project.pbxproj Wilgo/Features/Commitments/FinishedCycleReport WilgoTests/FinishedCycleReport/FinishedCycleReportBuilderTests.swift
git commit -m "refactor: remove grace period storage

#TargetModes

tracking: https://www.notion.so/refactor-target-disable-grace-3574b58e32c38071b420e3641a225d12"
```

---

### Phase 3 — Stage behavior

The goal of this phase is to route Disabled through target-disabled scheduling while keeping Inspiration Only aligned with Target On.

#### Commit 6 — refactor: route stage by effective target mode

**Files:**

- Modify: `Shared/Models/Commitment.swift`
- Create: `WilgoTests/Commitment/CommitmentInspirationOnlyStageTests.swift`
- Modify: `WilgoTests/Commitment/CommitmentTargetDisableTests.swift`

- [ ] **Step 1: Add Stage regression tests**

Create `CommitmentInspirationOnlyStageTests.swift` with:

```swift
import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite("Commitment.stageStatus - Inspiration Only", .serialized)
final class CommitmentInspirationOnlyStageTests {
    private func tod(hour: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2000
        comps.month = 1
        comps.day = 1
        comps.hour = hour
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps)!
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps)!
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, SlotSnooze.self, Tag.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    @Test("inspiration only active slot follows Target On current behavior")
    @MainActor
    func inspirationOnlyActiveSlotIsCurrent() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        let commitment = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 5, day: 1)),
            slots: [slot],
            target: Target(
                count: 2,
                mode: .inspirationOnly(
                    start: date(year: 2026, month: 5, day: 7),
                    until: date(year: 2026, month: 5, day: 8)
                )
            )
        )
        ctx.insert(commitment)
        ctx.insert(slot)

        let status = commitment.stageStatus(now: date(year: 2026, month: 5, day: 7, hour: 10))

        #expect(status.category == .current)
        #expect(status.behindCount == 1)
    }

    @Test("expired inspiration only follows On and can become metGoal")
    @MainActor
    func expiredInspirationOnlyBehavesAsOn() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 15), end: tod(hour: 17))
        let commitment = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 5, day: 1)),
            slots: [slot],
            target: Target(
                count: 1,
                mode: .inspirationOnly(
                    start: date(year: 2026, month: 5, day: 6),
                    until: date(year: 2026, month: 5, day: 7)
                )
            )
        )
        let checkIn = CheckIn(commitment: commitment, createdAt: date(year: 2026, month: 5, day: 7, hour: 10))
        ctx.insert(commitment)
        ctx.insert(slot)
        ctx.insert(checkIn)
        commitment.checkIns = [checkIn]

        let status = commitment.stageStatus(now: date(year: 2026, month: 5, day: 7, hour: 12))

        #expect(status.category == .metGoal)
    }
}
```

- [ ] **Step 2: Update stageStatus gate**

In `Commitment.stageStatus(now:)`, replace:

```swift
if !target.isEnabled {
    return targetDisabledStatus(now: now)
}
```

with:

```swift
let nowPsychDay = Time.startOfDay(for: now)
if effectiveTargetMode(on: nowPsychDay) == .disabled {
    return targetDisabledStatus(now: now)
}
```

Keep the rest of the target-on branch unchanged.

- [ ] **Step 3: Update target-disabled tests**

Change test fixtures from `Target(count: 3, isEnabled: false)` to:

```swift
Target(count: 3, mode: .disabled)
```

Keep compatibility initializer only if needed during transition.

- [ ] **Step 4: Run Stage tests**

Run:

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' -only-testing:WilgoTests/CommitmentInspirationOnlyStageTests -only-testing:WilgoTests/CommitmentTargetDisableTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Shared/Models/Commitment.swift WilgoTests/Commitment/CommitmentInspirationOnlyStageTests.swift WilgoTests/Commitment/CommitmentTargetDisableTests.swift
git commit -m "refactor: route stage by target mode

#TargetModes

tracking: https://www.notion.so/refactor-target-disable-grace-3574b58e32c38071b420e3641a225d12"
```

---

### Phase 4 — Form draft and save flows

The goal of this phase is to expose target modes in Add/Edit and preserve the current-cycle confirmation behavior.

#### Commit 7 — feat: save target modes from commitment forms

**Files:**

- Modify: `Wilgo/Features/Commitments/Form/CommitmentFormDraft.swift`
- Modify: `Wilgo/Features/Commitments/Form/CommitmentFormFields.swift`
- Modify: `Wilgo/Features/Commitments/Form/AddCommitmentView.swift`
- Modify: `Wilgo/Features/Commitments/Form/EditCommitmentView.swift`
- Modify: `Wilgo/Features/Commitments/GraceDialogModifier.swift`
- Modify: `WilgoTests/Commitment/CommitmentFormDraftTests.swift`

- [ ] **Step 1: Update form draft tests**

Add tests:

```swift
@Test("insert disabled saves disabled mode")
@MainActor
func insertDisabledSavesDisabledMode() throws {
    let container = try makeContainer()
    let context = container.mainContext
    var draft = CommitmentFormDraft(title: "Draw")
    draft.target = Target(count: 3, mode: .disabled)

    let commitment = draft.insertCommitment(in: context)

    #expect(commitment.target.configuredMode == .disabled)
}

@Test("insert inspiration only saves start and until")
@MainActor
func insertInspirationOnlySavesInterval() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let start = date(year: 2026, month: 5, day: 4)
    let until = date(year: 2026, month: 5, day: 11)
    var draft = CommitmentFormDraft(title: "Draw")
    draft.target = Target(count: 3, mode: .inspirationOnly(start: start, until: until))

    let commitment = draft.insertCommitment(in: context)

    #expect(commitment.target.configuredMode == .inspirationOnly(start: start, until: until))
}
```

- [ ] **Step 2: Simplify draft save signatures**

In `CommitmentFormDraft`, remove `gracePeriod`/period parameters from:

```swift
func insertCommitment(in modelContext: ModelContext) -> Commitment
func apply(to commitment: Commitment, in modelContext: ModelContext)
```

Save `target` directly:

```swift
target: target
```

and:

```swift
commitment.target = target
```

- [ ] **Step 3: Replace target toggle with mode picker**

In `CommitmentFormFields`, replace `Toggle("Enable target", isOn: targetEnabledBinding)` with segmented mode selection. Prefer a picker enum to avoid associated-value picker problems:

```swift
private enum TargetModeChoice: String, CaseIterable, Hashable {
    case on = "On"
    case inspirationOnly = "Inspiration Only"
    case disabled = "Disabled"
}
```

Map:

```swift
private var targetModeChoiceBinding: Binding<TargetModeChoice> {
    Binding(
        get: {
            switch target.configuredMode {
            case .on: return .on
            case .inspirationOnly: return .inspirationOnly
            case .disabled: return .disabled
            }
        },
        set: { choice in
            switch choice {
            case .on:
                target.setConfiguredMode(.on)
            case .disabled:
                target.setConfiguredMode(.disabled)
            case .inspirationOnly:
                target.setConfiguredMode(
                    .inspirationOnly(
                        start: currentCycleStart,
                        until: nextCycleStart
                    )
                )
            }
        }
    )
}
```

Add `currentCycleStart`, `nextCycleStart`, and an until picker for next cycle vs forever:

```swift
private var currentCycleStart: Date {
    let today = Time.startOfDay(for: Time.now())
    return cycle.startDayOfCycle(including: today)
}

private var nextCycleStart: Date {
    cycle.endDayOfCycle(including: currentCycleStart)
}
```

- [ ] **Step 4: Update Add flow**

In `AddCommitmentView.handleSaveTap()`, ask the current-cycle question only when `draft.target.configuredMode == .on`.

When user chooses not to count current cycle, mutate draft before save:

```swift
draft.target.setConfiguredMode(
    .inspirationOnly(
        start: graceDialog.cycleStart,
        until: graceDialog.cycleEnd
    )
)
```

Then call:

```swift
let commitment = draft.insertCommitment(in: modelContext)
```

- [ ] **Step 5: Update Edit flow**

In `EditCommitmentView.handleSaveTap()`, ask the current-cycle question only when rules changed and `draft.target.configuredMode == .on`.

When user chooses not to count current cycle, mutate `draftToSave.target` through `setConfiguredMode`:

```swift
draftToSave.target.setConfiguredMode(
    .inspirationOnly(start: graceDialog.cycleStart, until: graceDialog.cycleEnd)
)
```

Then call:

```swift
draftToSave.apply(to: commitment, in: modelContext)
```

- [ ] **Step 6: Rename visible dialog copy**

In `GraceDialogModifier.swift`, keep the component if useful but change visible strings:

```swift
Text("Should this current cycle count?")
Button("Count current cycle") { onConfirm(false) }
Button("Inspiration only until next cycle") { onConfirm(true) }
```

- [ ] **Step 7: Run focused tests and build**

Run:

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' -only-testing:WilgoTests/CommitmentFormDraftTests
xcodebuild build -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588'
```

Expected: tests pass and build succeeds.

- [ ] **Step 8: Manual verification**

On iPhone 17 simulator:

- Add commitment with Target On; verify current-cycle dialog appears.
- Add commitment with Inspiration Only until next cycle; verify no dialog appears.
- Add commitment with Inspiration Only forever; verify no dialog appears.
- Add commitment with Disabled; verify no dialog appears.
- Edit On commitment target/cycle rules; verify current-cycle dialog appears.

- [ ] **Step 9: Commit**

```bash
git add Wilgo/Features/Commitments/Form Wilgo/Features/Commitments/GraceDialogModifier.swift WilgoTests/Commitment/CommitmentFormDraftTests.swift
git commit -m "feat: expose target modes in commitment forms

#TargetModes

tracking: https://www.notion.so/refactor-target-disable-grace-3574b58e32c38071b420e3641a225d12"
```

---

### Phase 5 — Cleanup and verification

The goal of this phase is to remove remaining grace language from app/test source and verify the full target-mode slice.

#### Commit 8 — chore: remove grace language from target modes

**Files:**

- Modify files found by `rg -n "grace|Grace" Wilgo Shared WilgoTests`

- [ ] **Step 1: Search remaining grace references**

Run:

```bash
rg -n "grace|Grace" Wilgo Shared WilgoTests
```

Expected: only compatibility comments or unrelated historical text remain. Rename user-facing strings and test names to Inspiration Only.

- [ ] **Step 2: Run focused target-mode suites**

Run:

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' -only-testing:WilgoTests/TargetModeTests -only-testing:WilgoTests/CommitmentFormDraftTests -only-testing:WilgoTests/CommitmentTargetDisableTests -only-testing:WilgoTests/CommitmentInspirationOnlyStageTests -only-testing:WilgoTests/FinishedCycleReportBuilderTests -only-testing:WilgoTests/FinishedCycleReportPresentationStateTests
```

Expected: PASS.

- [ ] **Step 3: Run full suite**

Run:

```bash
./test-with-cleanup.sh
```

Expected: full suite passes except any documented pre-existing failure. If `CommitmentStageSnoozeTests/stageStatus_snoozeDoesNotAffectFutureOccurrence()` fails, record it separately as pre-existing unless fresh evidence shows this branch changed it.

- [ ] **Step 4: Manual verification**

On iPhone 17 simulator:

- Finish a cycle while Inspiration Only is active; report shows `actual/target · inspiration only` and consumes no PT.
- Delay report across an expired Inspiration Only interval; expired cycles after `until` report as On.
- Complete report; reopen app; expired finite Inspiration Only mode is normalized to On.
- Stage for Inspiration Only follows Target On and can enter `.metGoal`.
- Stage for Disabled follows target-disabled scheduling.

- [ ] **Step 5: Commit**

```bash
git add Wilgo Shared WilgoTests documentation/TargetModes.md
git commit -m "chore: clean up target mode language

#TargetModes

tracking: https://www.notion.so/refactor-target-disable-grace-3574b58e32c38071b420e3641a225d12"
```

---

## Critical Files

| File                                                                               | Role                                                                 |
| ---------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `Shared/Models/TargetMode.swift`                                                   | TargetMode enum and mode helper methods                              |
| `Shared/Models/GracePeriod.swift`                                                  | Legacy grace model removed after migration                           |
| `Shared/Models/Commitment.swift`                                                   | Target storage, effective mode, Stage routing, report classification |
| `Wilgo/Features/Commitments/FinishedCycleReport/FinishedCycleReportModifier.swift` | Report finalization, watermark, target-mode normalization            |
| `Wilgo/Features/Commitments/FinishedCycleReport/PreTokenReportBuilder.swift`       | Per-cycle Inspiration Only classification                            |
| `Wilgo/Features/Commitments/Form/CommitmentFormDraft.swift`                        | Form persistence                                                     |
| `Wilgo/Features/Commitments/Form/CommitmentFormFields.swift`                       | Target mode UI                                                       |

## Dependency Graph

```text
Commit 0: FinishedCycleReport finalization flow
    |
    +-- Commit 1: TargetMode model
            |
            +-- Commit 2: target-mode API hardening
            |       |
            |       +-- Commit 3: report classification
            |               |
            |               +-- Commit 4: post-report normalization
            |                       |
            |                       +-- Commit 5: remove grace storage
            |                               |
            |                               +-- Commit 6: Stage routing
            |                                       |
            |                                       +-- Commit 7: form UX and save flows
            |                                               |
            |                                               +-- Commit 8: cleanup and verification
```

Commits are sequential because they touch overlapping model/report/form semantics.

## Self-Review

- PRD coverage: On, Inspiration Only until date/forever, Disabled, add/edit prompts, expiration, reports, Stage default, and non-goals are mapped to tasks.
- Red-flag scan: each commit has explicit files, focused tests, commands, and expected results.
- Type consistency: `TargetMode.inspirationOnly(start:until:)`, `effectiveMode(on:)`, and `normalized(afterReportedThrough:)` are introduced in Phase 1 and reused consistently in later phases.
