# Scheduled Live Activities (per-occurrence cards) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**PRD:** [AlarmKit LiveActivity — decision record](https://www.notion.so/AlarmKit-LiveActivity-3914b58e32c380398de6ca5ac5328a44) (add a back-link to this file from that page)
**Tracking:** [https://www.notion.so/Change-LiveActivity-to-be-per-slot-3924b58e32c380c48a82de97a20cedd5?source=copy_link](https://www.notion.so/Change-LiveActivity-to-be-per-slot-3924b58e32c380c48a82de97a20cedd5?source=copy_link)
**Tag**: `#scheduledLA`

**Goal:** Replace the broken "BG task starts the Live Activity" design with iOS 26 _scheduled_ Live Activities: one card per slot occurrence, pre-queued while the app process runs, started by the system on time.

**Architecture:** A pure planner (`LiveActivityPlanner`) turns commitments into a list of planned per-occurrence cards; a thin ActivityKit shell (`LiveActivityRefresher.refresh`) diffs that plan against `Activity<NowAttributes>.activities` and ends/requests as needed. Every existing wake path (scene phase, check-in/snooze intents, `CommitmentChangeRefresher`) already funnels into `LiveActivityRefresher.refresh`, so wiring is nearly free.

**Tech Stack:** ActivityKit (iOS 26 `Activity.request(..., alertConfiguration:start:)`), WidgetKit, SwiftData, Swift Testing.

---

## Context

Decisions from the PRD (Notion decision record, 2026-07-03):

1. **The old design is structurally broken.** `Activity.request` throws `.visibility` from the background; a BGAppRefreshTask can never _start_ an LA. Chaining BG tasks was fragile on top of impossible.
2. **iOS 26 scheduled LAs are the new backbone.** `Activity.request(attributes:content:pushType:style:alertConfiguration:start:)` queues a future start that the system fires even if the app is dead. Only _starts_ are schedulable — never updates. One `staleDate` flip per card is the only other pre-programmable event.
3. **One card per slot occurrence** (no merging in v1). Primary reason: each occurrence becomes its own independently system-scheduled event — reliability through independence. Overlapping slots = multiple cards; `relevanceScore` (nearest deadline wins) picks the Dynamic Island owner.
4. **Soft end**: cards flip to a visually "ended" state via `staleDate` (`context.isStale` in the widget); true removal happens at the next app wake.
5. **Scope cut for this round (3Sauce, 2026-07-03): ignore the BG-task part.** We validate the design while the app process gets to run (foreground + intents). The existing BG task keeps calling the new refresh — harmless janitor (its requests fail silently in background; ends succeed) — but we build nothing new for it.
6. Out of scope here: AlarmKit tier (separate effort), notification/LA double-alert dedup at slot start (evaluate in dogfood first), merging identical-window cards (deferred; see PRD).

---

## Architecture Summary

### The one-sentence version

**Whenever the app gets a chance to run, it makes the Live Activity world match what the database says should be true — then hands iOS a pre-loaded queue of future cards and goes back to sleep.**

### The mental model (restocking a vending machine)

Think of a vending machine you restock whenever you happen to walk by:

1. **The plan ("what should exist")** — look at the commitments and write down the next ~8 slot occurrences: *"Gym card should appear at 4pm and look ended at 8pm; Supplement card at 6–7pm; …"* Each entry says what the card shows, when it appears, and when it flips to "Ended". This is `LiveActivityPlanner.plan` — just a list-maker, touches nothing.
2. **The comparison ("what's the difference")** — hold that list next to the cards that currently exist (visible ones + ones already queued in iOS):
   - Card matches a list entry → **leave it alone** (no flicker).
   - Card exists but isn't on the list (checked in, edited, window long gone) → **remove it**.
   - List entry has no card → **create it**: future ones are handed to iOS with "start this at 4pm" (iOS fires it even if the app is dead by then); an already-open one is shown immediately.
   That's `LiveActivityPlanner.diff` — nothing more than keep / remove / add.
3. **Between runs, iOS does everything alone** — starts the queued cards on time, ticks the countdown, flips each card to "Ended" at its stale date. No background tasks, no chaining. The app's only job is restocking the queue whenever it happens to run: app open, app close, every Done/Snooze tap.

**Why this shape is the reliable one:** the old design was a relay race — each background task had to wake up and hand off to the next, and one dropped baton killed the chain forever. The new design has **no memory and no chain**: every single run rebuilds the correct state from scratch, so it doesn't matter which runs get skipped or in what order things fire — any one wake repairs everything. This is also why planned content must be *deterministic* (same inputs → byte-identical card content): determinism is what lets the comparison recognize "this card is already right, don't touch it" instead of destroying and recreating everything each time.

The only true limit: iOS's queue is small (~5 cards). So we always load the *nearest* occurrences, and every interaction with any card refills the queue. Total neglect for days drains the LA layer — the notification floor (and later, the AlarmKit tier) still fires then.

### Data flow

```
                 (pure, unit-tested)                        (thin ActivityKit shell)
 commitments ──▶ LiveActivityPlanner.plan ──▶ [PlannedLiveActivity] ──▶ LiveActivityRefresher.refresh
                        │                                                    │ diff against
                        └──▶ LiveActivityPlanner.diff ◀── (id, ContentState) ┘ Activity.activities
                                     │
                          (toEnd ids, toRequest planned)
                                     │
                     end(.immediate) / request(scheduled or immediate)
```

- **Plan**: enumerate usable occurrences per active-for-reminders commitment over a 14-day horizon (reusing `Commitment.slotOccurrences`, same gate as `SlotStartNotificationScheduler`), keep the nearest `maxPlanned = 8`. An occurrence already open now becomes an _immediate_ request (foreground start); a future one becomes a _scheduled_ request.
- **Diff**: an existing activity whose `ContentState` exactly equals a planned state is kept (no churn); everything else is ended; unmatched planned items are requested nearest-first until ActivityKit throws (capacity discovery — the real queue limit is undocumented, so we request until `targetMaximumExceeded` instead of hardcoding it).
- **Deterministic content**: encouragement is picked by a stable per-(slot, psych-day) index, not `randomElement()`, so re-planning produces identical `ContentState` and the diff doesn't end+recreate unchanged cards every wake. Cycle progress (`checkInCount`/`targetCount`, nil when the target is disabled) is likewise baked in: it's deterministic given the store, and every store change runs through the app process, which re-plans — a check-in therefore refreshes the count on the card via end+re-request.
- **Card lifecycle**: starts at occurrence start (system alert — mandatory for scheduled LAs), shows a live countdown via `Text(timerInterval:)`/`ProgressView(timerInterval:)` (no runtime needed), flips to "Ended ✓" at `staleDate == occurrence.end`, is removed at the next wake.

---

## Design Decisions

### One card per occurrence, identity = `ContentState` equality

**Decision:** The diff keys on whole-`ContentState` equality (which contains `slotId` + `windowStart`/`windowEnd`). Match → keep; mismatch → end + re-request.

**Why not key on `slotId` alone?** A slot is a *template*, not a firing: the same slot fires today and tomorrow, and both cards coexist in `Activity.activities` (today's live card + tomorrow's pending scheduled one). Keyed by `slotId` alone, the diff would match today's card against tomorrow's planned entry across the day boundary — wrong window, wrong `staleDate`. `slotId + windowStart` (both inside `ContentState`) names *this slot's firing on this day*, mirroring `SlotOccurrence`'s own identity (`slot + psychDay`).

**Why end+re-request on mismatch instead of `update()`?** (Decided with 3Sauce, 2026-07-03 — reliability over polish.) End+re-request is one code path that works identically for live and pending cards, is idempotent, and depends on no unverified behavior (`update()` on a *pending* scheduled activity is unverified v1 API). Its only cost: a pending card's recreation is invisible; a live card blinks once (no alert — immediate requests don't alert; no capacity risk — ends run before requests). With `checkInCount` on the card, the visible case is "tap Done (1 of N) → card blinks while the count refreshes." If that blip proves annoying in dogfood, an in-place `update()` bucket for *started* activities is a small additive change (one diff bucket, one `activity.update(content)` call, two tests) — tracked in Known follow-ups; verify update-on-pending semantics only if/when that lands.

**Risk:** a pending (not yet started) activity might not expose `content.state` for diffing. Mitigation: manual verification step in Commit 4 checks pending activities round-trip; if they don't, fall back to "end all pending + re-request" (still correct, minor churn) — a one-line change in `refresh`.

### Ordering by absolute deadline — Stage's `remainingFraction` sort cannot be reused

**Decision:** `relevanceScore = 4e9 − windowEnd` ("ends soonest ranks highest") decides the Dynamic Island owner and Lock Screen stack order. This deliberately does NOT reuse the Stage's Current-bucket sort (`StageCharacterization.stageBuckets`, sorted by `remainingFraction(at: now)`), even though both express "most urgent first."

**Why (discussed with 3Sauce, 2026-07-03):** `remainingFraction` is a ratio that changes every minute, and fraction orderings *cross over time* (e.g. slot A 9:00–17:00 vs slot B 10:00–11:00: at 10:00 A ranks first, by 10:30 B does). The Stage may use it because it re-sorts on every render. A Live Activity's `relevanceScore` is **frozen at request time** — re-scoring requires app runtime, the very dependency this design eliminates. So the ordering rule must be computable once and stay correct forever: a time-invariant fact of the window. Among those, absolute deadline is the one matching the Stage's intent.

**Accepted divergence:** when two cards are open simultaneously with very different durations, Stage (fraction, live-sorted) and LA (deadline, frozen) can briefly disagree on which is "most urgent." Each is optimal for its own medium; both agree in the common case.

### Discover the queue cap by requesting until throw

**Decision:** Plan up to 8 cards; request nearest-first; stop on first `ActivityAuthorizationError`. No hardcoded "5".

**Why not hardcode the known ~5 limit?** It's undocumented and may differ by device/OS. Requesting nearest-first means whatever the cap is, the most imminent occurrences always win.

**Risk:** a non-capacity error (e.g. `.denied`) also stops the loop. That's correct behavior for `.denied` (nothing else would succeed either).

### Deterministic encouragement (stable per slot + day)

**Decision:** `encouragements[dayOrdinal(psychDay) % count]` instead of `randomElement()`.

**Why not random?** Random text makes every re-plan produce a different `ContentState`, so the diff would end+recreate every card on every wake (visible flicker, alert re-fires). Determinism keeps variety across days and stability within a day.

### Keep entry points; rewrite internals

**Decision:** `LiveActivityRefresher.refresh(context:now:)` keeps its name and signature and becomes the reconciler. `NowLiveActivityManager` and all call sites stay put.

**Why not a new** `ReminderCoordinator` **now?** YAGNI for this scope; the coordinator idea matters when the AlarmKit tier lands. Zero call-site churn also keeps this diff reviewable.

---

## Major Model Changes

| Entity                                             | Change                                                                                                                                                   |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Shared/Widget/NowAttributes.swift`                | `ContentState` becomes per-occurrence: drop `secondaryTitles`; add `windowStart`/`windowEnd: Date` (timers, stale look, diff identity) and `checkInCount`/`targetCount: Int?` (cycle progress badge, nil when target disabled) |
| **New:** `Shared/Widget/LiveActivityPlanner.swift` | Pure planning + diffing: `PlannedLiveActivity`, `plan`, `diff`, `relevanceScore`, `encouragement`                                                        |
| `Shared/Widget/LiveActivityRefresher.swift`        | Rewritten as the diff-driven reconciler; scheduled + immediate requests, `AlertConfiguration`, capacity-throw handling                                   |
| `WidgetExtension/NowLiveActivity.swift`            | Per-occurrence card UI: countdown timer + progress, `context.isStale` "Ended ✓" state, secondary-titles UI removed                                       |

No SwiftData schema changes. No `Info.plist` changes (`NSSupportsLiveActivities` already set).

---

## Commit Plan

### Phase 1 — Content model + UI (visible early, per repo rule "UI change first")

#### Commit 1 — Per-occurrence ContentState + card UI (timer, stale state)

**Modify:** `Shared/Widget/NowAttributes.swift` — replace `ContentState`:

```swift
struct NowAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Title of the commitment this occurrence belongs to.
        var commitmentTitle: String
        /// Current slot time range, e.g. "9:00 AM – 11:00 AM".
        var slotTimeText: String

        /// UUID of the commitment — used by Live Activity buttons to deep-link back into the app.
        var commitmentId: UUID
        /// UUID of the slot.
        var slotId: UUID

        /// Concrete occurrence window. Drives the countdown timer / progress rendering and,
        /// together with `slotId`, gives each card its per-occurrence identity for reconciling.
        var windowStart: Date
        var windowEnd: Date

        /// Deterministic per-(slot, psych-day) encouragement. Nil if none set.
        var encouragementText: String?

        /// Cycle progress at the time this content was built: check-ins done in the occurrence's
        /// cycle / target count. Both nil when the target is disabled. Safe to freeze: counts only
        /// change through the app process (check-in / undo paths), and every such path triggers a
        /// reconcile, so a visible card's count can never silently go stale.
        var checkInCount: Int?
        var targetCount: Int?
    }
}
```

**Modify:** `Shared/Widget/LiveActivityRefresher.swift` — keep the current single-card flow compiling on the new state (full rewrite comes in Commit 4). Replace `makeContentState(from:)`:

```swift
    // precondition: currentSlots is not empty (each has an open `currentOccurrence`)
    static func makeContentState(
        from currentSlots: [CommitmentCharacteristics]
    ) -> NowAttributes.ContentState {
        let first = currentSlots.first!
        let commitment = first.commitment
        let occurrence = first.currentOccurrence!
        // Interim duplicate of the count logic — Commit 4 deletes this whole function in favor of
        // `LiveActivityPlanner.makeState`/`progressCounts`.
        let checkInCount: Int?
        let targetCount: Int?
        if case .disabled = commitment.target.configuredMode {
            checkInCount = nil
            targetCount = nil
        } else {
            checkInCount = commitment.checkInsInCycle(containing: occurrence.start).count
            targetCount = commitment.target.count
        }
        return NowAttributes.ContentState(
            commitmentTitle: commitment.title,
            slotTimeText: occurrence.timeOfDayText,
            commitmentId: commitment.id,
            slotId: occurrence.slot.id,
            windowStart: occurrence.start,
            windowEnd: occurrence.end,
            encouragementText: commitment.encouragements.randomElement(),
            checkInCount: checkInCount,
            targetCount: targetCount
        )
    }
```

**Modify:** `WidgetExtension/NowLiveActivity.swift`

- Delete `formatSecondaryTitlesLine`, `SecondaryTitlesLineBudget`, `SecondaryCommitmentsLine`, and the `extraCount` parameter/badge of `CompactTrailingTitle` (keep the title-only version).
- Add the window line + stale handling + progress count badge. New shared subviews:

```swift
private struct ProgressCountBadge: View {
    let checkInCount: Int
    let targetCount: Int

    var body: some View {
        Text("\(checkInCount)/\(targetCount)")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.15)))
            .accessibilityLabel("\(checkInCount) of \(targetCount) done this cycle")
    }
}
```

```swift
private struct WindowStatusLine: View {
    let state: NowAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if isStale {
            Label("Ended", systemImage: "checkmark.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                Text(timerInterval: state.windowStart...state.windowEnd, countsDown: true)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.tint)
                ProgressView(timerInterval: state.windowStart...state.windowEnd, countsDown: true) {
                } currentValueLabel: {
                }
                .progressViewStyle(.linear)
                .tint(.accentColor)
            }
        }
    }
}
```

- Lock-screen view: replace the `secondaryLine` usage with `WindowStatusLine(state: context.state, isStale: context.isStale)` under the `slotTimeText` row; hide `SnoozeCapsuleLink`/`DoneCapsuleLink` when `context.isStale` (an ended window is not actionable):

```swift
        ActivityConfiguration(for: NowAttributes.self) { context in
            HStack(alignment: .top, spacing: 12) {
                LiveActivitySparkleIcon(diameter: 40)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(context.state.commitmentTitle)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if let done = context.state.checkInCount,
                                    let target = context.state.targetCount
                                {
                                    ProgressCountBadge(checkInCount: done, targetCount: target)
                                }
                            }
                            Text(context.state.slotTimeText)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            if let encouragement = context.state.encouragementText, !context.isStale {
                                Text(encouragement)
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                                    .italic()
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        if !context.isStale {
                            HStack(spacing: 6) {
                                SnoozeCapsuleLink(slotId: context.state.slotId)
                                DoneCapsuleLink(commitmentId: context.state.commitmentId)
                            }
                        }
                    }
                    WindowStatusLine(state: context.state, isStale: context.isStale)
                }
            }
            .padding(.vertical, 6)
            .activityBackgroundTint(Color(.systemFill))
            .activitySystemActionForegroundColor(Color.primary)
        }
```

- Dynamic Island: same substitutions — `.center` region loses the secondary line, gains `WindowStatusLine`, and its title row gains the same `ProgressCountBadge` (wrapped in the same `if let done/target`); `.bottom` buttons wrapped in `if !context.isStale`; `compactTrailing` uses the badge-less `CompactTrailingTitle(title: context.state.commitmentTitle)`.
- Update the `#Preview` `withCommitment` state to the new initializer (use `Date.now` / `Date.now.addingTimeInterval(2 * 3600)` for the window; `checkInCount: 1, targetCount: 3` to preview the badge).

**Modify:** `WilgoTests/Notifications/LiveActivityRefresherTests.swift`

- Delete `multipleCurrent_primaryPlusSecondaries` (secondary titles no longer exist).
- In `singleCurrent_mapsPrimaryFields`, replace the `secondaryTitles` assertion with window assertions:

```swift
        #expect(state.windowStart == current[0].currentOccurrence?.start)
        #expect(state.windowEnd == current[0].currentOccurrence?.end)
        #expect(state.checkInCount == 0)  // Target(count: 1), no check-ins yet
        #expect(state.targetCount == 1)
```

**Steps:**

- [ ] **Step 1:** Apply the four file changes above.
- [ ] **Step 2:** Run the touched tests:
      `xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' -only-testing:WilgoTests/LiveActivityRefresherTests`
      Expected: PASS.
- [ ] **Step 3:** Build the widget extension too (whole-project build): `xcodebuild build -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588'`
      Expected: BUILD SUCCEEDED (stale SourceKit warnings ignorable per CLAUDE.md).
- [ ] **Step 4:** Commit:

```bash
git add Shared/Widget/NowAttributes.swift Shared/Widget/LiveActivityRefresher.swift WidgetExtension/NowLiveActivity.swift WilgoTests/Notifications/LiveActivityRefresherTests.swift
git commit -m "Per-occurrence Live Activity card: window in ContentState, countdown + stale UI, drop secondary titles

#scheduledLA
tracking: https://www.notion.so/Change-LiveActivity-to-be-per-slot-3924b58e32c380c48a82de97a20cedd5"
```

**Manual verification (3Sauce):** run the app on the iPhone 17 simulator with a commitment whose slot is open now → lock screen / Dynamic Island shows the card with a ticking countdown and progress bar; no secondary-titles line anywhere.

---

### Phase 2 — Pure planner (parallelizable commits 2 & 3 after commit 1)

#### Commit 2 — `LiveActivityPlanner.plan`: occurrences → planned cards

**Create:** `Shared/Widget/LiveActivityPlanner.swift`

```swift
import Foundation

/// One Live Activity card the app intends to exist: either already-open (request immediately,
/// app is in foreground / an intent) or future (request with `start:` so the system starts it
/// even if the app is dead). Pure value — building and diffing these is unit-tested; only the
/// thin shell in `LiveActivityRefresher` touches ActivityKit.
struct PlannedLiveActivity: Equatable {
    let state: NowAttributes.ContentState
    /// System start date. Nil = the occurrence is already open → request immediately.
    let scheduledStart: Date?
    /// Occurrence end: the card flips to the stale ("Ended") rendering here with no app runtime.
    let staleDate: Date
    /// Higher = owns the Dynamic Island. Earlier deadline → higher score.
    let relevanceScore: Double
}

enum LiveActivityPlanner {
    /// More than any plausible device queue cap (undocumented, ~5): the refresher requests
    /// nearest-first and stops at the first capacity throw, so planning extra is free.
    static let maxPlanned = 8
    /// Same enumeration horizon as `SlotStartNotificationScheduler` — see its rationale.
    static let horizonDays = 14

    /// The cards that should exist at `now`: the nearest `maxPlanned` usable occurrences across
    /// all reminder-active commitments, each mapped to a per-occurrence card. Occurrences whose
    /// window is already open (start ≤ now < end) come first with `scheduledStart == nil`.
    static func plan(
        commitments: [Commitment],
        now: Date,
        calendar: Calendar = Time.calendar
    ) -> [PlannedLiveActivity] {
        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: now) ?? now
        let occurrences: [(SlotOccurrence, Commitment)] =
            commitments
            .filter { $0.isActiveForReminders(now: now) }
            .flatMap { c in c.slotOccurrences(from: now, until: horizon).map { ($0, c) } }
            .filter { $0.0.end > now }  // softFrom lets open occurrences in; drop fully-past ones
            .sorted { $0.0 < $1.0 }
        return occurrences.prefix(maxPlanned).map { occ, commitment in
            PlannedLiveActivity(
                state: makeState(occurrence: occ, commitment: commitment),
                scheduledStart: occ.start > now ? occ.start : nil,
                staleDate: occ.end,
                relevanceScore: relevanceScore(windowEnd: occ.end)
            )
        }
    }

    static func makeState(
        occurrence: SlotOccurrence, commitment: Commitment
    ) -> NowAttributes.ContentState {
        let counts = progressCounts(for: commitment, occurrence: occurrence)
        return NowAttributes.ContentState(
            commitmentTitle: commitment.title,
            slotTimeText: occurrence.timeOfDayText,
            commitmentId: commitment.id,
            slotId: occurrence.slot.id,
            windowStart: occurrence.start,
            windowEnd: occurrence.end,
            encouragementText: encouragement(for: commitment, occurrence: occurrence),
            checkInCount: counts.checkInCount,
            targetCount: counts.targetCount
        )
    }

    /// Cycle progress baked into the card: check-ins in the **occurrence's own** cycle (a future
    /// occurrence may fall in a future cycle → counts start at 0) / the target count. Nil pair when
    /// the target is disabled. Safe to freeze: counts only change through the app process
    /// (check-in / undo paths), and every such path triggers a reconcile — the diff then ends and
    /// re-requests the card with the fresh count.
    static func progressCounts(
        for commitment: Commitment, occurrence: SlotOccurrence
    ) -> (checkInCount: Int?, targetCount: Int?) {
        if case .disabled = commitment.target.configuredMode {
            return (nil, nil)
        }
        return (
            commitment.checkInsInCycle(containing: occurrence.start).count,
            commitment.target.count
        )
    }

    /// Deterministic pick: rotates daily, stable within a day. Randomness would change the
    /// `ContentState` on every re-plan, making the diff end+recreate unchanged cards (flicker,
    /// re-fired start alerts).
    static func encouragement(
        for commitment: Commitment, occurrence: SlotOccurrence
    ) -> String? {
        let all = commitment.encouragements
        guard !all.isEmpty else { return nil }
        let dayOrdinal = Int(occurrence.psychDay.timeIntervalSince1970 / 86_400)
        let index = ((dayOrdinal % all.count) + all.count) % all.count  // non-negative mod
        return all[index]
    }

    /// Earlier deadline → higher score → owns the Dynamic Island / tops the Lock Screen stack.
    /// Anchored so scores stay positive for any date before year ~2096.
    static func relevanceScore(windowEnd: Date) -> Double {
        max(0, 4_000_000_000 - windowEnd.timeIntervalSince1970)
    }
}
```

**Create:** `WilgoTests/Notifications/LiveActivityPlannerTests.swift`

```swift
import Foundation
import SwiftData
import Testing
@testable import Wilgo

/// Unit tests for the pure planning half of the scheduled-Live-Activity design.
/// The ActivityKit side (request/end) cannot run in the test host; it is covered by
/// on-device manual verification (see the implementation plan).
@Suite(.serialized)
final class LiveActivityPlannerTests {
    private func tod(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2000
        c.month = 1
        c.day = 1
        c.hour = hour
        c.minute = minute
        return Calendar.current.date(from: c)!
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        return Calendar.current.date(from: c)!
    }

    @MainActor
    private func makeCommitment(
        title: String,
        slots: [Slot],
        encouragements: [String] = [],
        in ctx: ModelContext
    ) -> Commitment {
        let anchor = date(year: 2026, month: 1, day: 1)
        let c = Commitment(
            title: title,
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: slots,
            target: Target(count: 1),
            isRemindersEnabled: true
        )
        c.encouragements = encouragements
        ctx.insert(c)
        for s in slots { ctx.insert(s) }
        return c
    }

    @Test("open occurrence → immediate (nil scheduledStart); future → scheduled at its start")
    @MainActor func openVsFutureStart() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(
            title: "Draw",
            slots: [Slot(start: tod(hour: 9), end: tod(hour: 11))],
            in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)  // inside today's 9–11

        let planned = LiveActivityPlanner.plan(commitments: [c], now: now)

        #expect(planned.count >= 2)
        #expect(planned[0].scheduledStart == nil)  // today's open occurrence
        #expect(planned[0].staleDate == date(year: 2026, month: 3, day: 5, hour: 11))
        #expect(planned[1].scheduledStart == date(year: 2026, month: 3, day: 6, hour: 9))
    }

    @Test("plan caps at maxPlanned nearest occurrences")
    @MainActor func capsAtMaxPlanned() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(
            title: "Draw",
            slots: [Slot(start: tod(hour: 9), end: tod(hour: 11))],  // daily → 14 in horizon
            in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 8)

        let planned = LiveActivityPlanner.plan(commitments: [c], now: now)

        #expect(planned.count == LiveActivityPlanner.maxPlanned)
        // Nearest-first ordering.
        let starts = planned.map { $0.scheduledStart ?? now }
        #expect(starts == starts.sorted())
    }

    @Test("reminder-inactive commitments are excluded")
    @MainActor func remindersGateApplies() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(
            title: "Draw",
            slots: [Slot(start: tod(hour: 9), end: tod(hour: 11))],
            in: container.mainContext)
        c.isRemindersEnabled = false
        let now = date(year: 2026, month: 3, day: 5, hour: 8)

        #expect(LiveActivityPlanner.plan(commitments: [c], now: now).isEmpty)
    }

    @Test("state carries occurrence window + ids; relevance favors earlier deadline")
    @MainActor func stateFieldsAndRelevance() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let a = makeCommitment(
            title: "Ends sooner",
            slots: [Slot(start: tod(hour: 9), end: tod(hour: 10))], in: ctx)
        let b = makeCommitment(
            title: "Ends later",
            slots: [Slot(start: tod(hour: 9), end: tod(hour: 12))], in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 9).addingTimeInterval(30 * 60)

        let planned = LiveActivityPlanner.plan(commitments: [a, b], now: now)
        let sooner = try #require(planned.first { $0.state.commitmentTitle == "Ends sooner" })
        let later = try #require(planned.first { $0.state.commitmentTitle == "Ends later" })

        #expect(sooner.state.commitmentId == a.id)
        #expect(sooner.state.slotId == a.slots[0].id)
        #expect(sooner.state.windowStart == date(year: 2026, month: 3, day: 5, hour: 9))
        #expect(sooner.state.windowEnd == date(year: 2026, month: 3, day: 5, hour: 10))
        #expect(sooner.relevanceScore > later.relevanceScore)
    }

    @Test("encouragement is deterministic for a given slot + day")
    @MainActor func encouragementDeterministic() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(
            title: "Draw",
            slots: [Slot(start: tod(hour: 9), end: tod(hour: 11))],
            encouragements: ["a", "b", "c"],
            in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)

        let first = LiveActivityPlanner.plan(commitments: [c], now: now)
        let second = LiveActivityPlanner.plan(commitments: [c], now: now)

        #expect(first[0].state == second[0].state)
        #expect(first[0].state.encouragementText != nil)
        // Different days may rotate; same day must not.
    }

    @Test("progress counts: baked from the occurrence's own cycle; nil when target disabled")
    @MainActor func progressCountsBaked() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let c = makeCommitment(
            title: "Draw",
            slots: [Slot(start: tod(hour: 9), end: tod(hour: 11))],
            in: ctx)
        c.target = Target(count: 3)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        CheckIn.insert(
            commitment: c, createdAt: date(year: 2026, month: 3, day: 5, hour: 9), into: ctx)

        let planned = LiveActivityPlanner.plan(commitments: [c], now: now)
        #expect(planned[0].state.checkInCount == 1)  // today's open occurrence, 1 of 3 done
        #expect(planned[0].state.targetCount == 3)
        #expect(planned[1].state.checkInCount == 0)  // tomorrow = next daily cycle, fresh count
        #expect(planned[1].state.targetCount == 3)

        let noTarget = makeCommitment(
            title: "NoTarget",
            slots: [Slot(start: tod(hour: 9), end: tod(hour: 11))],
            in: ctx)
        noTarget.target = Target(count: 1, mode: .disabled)
        let plannedNoTarget = LiveActivityPlanner.plan(commitments: [noTarget], now: now)
        #expect(plannedNoTarget[0].state.checkInCount == nil)
        #expect(plannedNoTarget[0].state.targetCount == nil)
    }
}
```

**Steps:**

- [ ] **Step 1:** Create the test file above (planner not yet created).
- [ ] **Step 2:** Run: `xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' -only-testing:WilgoTests/LiveActivityPlannerTests`
      Expected: FAIL to compile ("cannot find 'LiveActivityPlanner'").
- [ ] **Step 3:** Create `Shared/Widget/LiveActivityPlanner.swift` as above.
- [ ] **Step 4:** Re-run the same command. Expected: PASS (all 6 tests).
- [ ] **Step 5:** Commit:

```bash
git add Shared/Widget/LiveActivityPlanner.swift WilgoTests/Notifications/LiveActivityPlannerTests.swift
git commit -m "LiveActivityPlanner.plan: pure occurrences→planned-cards mapping with deterministic content

#scheduledLA
tracking: https://www.notion.so/Change-LiveActivity-to-be-per-slot-3924b58e32c380c48a82de97a20cedd5"
```

---

#### Commit 3 — `LiveActivityPlanner.diff`: existing activities vs plan

**Modify:** `Shared/Widget/LiveActivityPlanner.swift` — add inside the enum:

```swift
    /// Reconciliation decision, computed purely so it can be unit-tested. An existing activity
    /// whose state exactly equals a planned state is kept (zero churn on unchanged cards —
    /// this is why planned content must be deterministic); every other existing activity is
    /// ended; every unmatched planned card is requested.
    static func diff(
        existing: [(id: String, state: NowAttributes.ContentState)],
        planned: [PlannedLiveActivity]
    ) -> (toEnd: [String], toRequest: [PlannedLiveActivity]) {
        var toRequest = planned
        var toEnd: [String] = []
        for activity in existing {
            if let matched = toRequest.firstIndex(where: { $0.state == activity.state }) {
                toRequest.remove(at: matched)
            } else {
                toEnd.append(activity.id)
            }
        }
        return (toEnd, toRequest)
    }
```

**Modify:** `WilgoTests/Notifications/LiveActivityPlannerTests.swift` — add tests (they build states via a small helper, no SwiftData needed):

```swift
    private func state(title: String, slotId: UUID, start: Date, end: Date)
        -> NowAttributes.ContentState
    {
        NowAttributes.ContentState(
            commitmentTitle: title, slotTimeText: "9:00 AM – 11:00 AM",
            commitmentId: UUID(), slotId: slotId,
            windowStart: start, windowEnd: end, encouragementText: nil,
            checkInCount: nil, targetCount: nil)
    }

    private func plannedItem(_ s: NowAttributes.ContentState) -> PlannedLiveActivity {
        PlannedLiveActivity(
            state: s, scheduledStart: s.windowStart, staleDate: s.windowEnd,
            relevanceScore: 1)
    }

    @Test("diff keeps exact matches, ends orphans, requests the rest")
    func diffPartitions() {
        let slotA = UUID()
        let slotB = UUID()
        let d1 = Date(timeIntervalSince1970: 1_000_000)
        let d2 = Date(timeIntervalSince1970: 1_010_000)
        let matching = state(title: "A", slotId: slotA, start: d1, end: d2)
        let orphanState = state(title: "gone", slotId: UUID(), start: d1, end: d2)
        let newState = state(title: "B", slotId: slotB, start: d2, end: d2.addingTimeInterval(3600))

        let (toEnd, toRequest) = LiveActivityPlanner.diff(
            existing: [(id: "act-1", state: matching), (id: "act-2", state: orphanState)],
            planned: [plannedItem(matching), plannedItem(newState)]
        )

        #expect(toEnd == ["act-2"])
        #expect(toRequest.map(\.state) == [newState])
    }

    @Test("diff with changed content for same slot ends the old and requests the new")
    func diffContentChanged() {
        let slot = UUID()
        let d1 = Date(timeIntervalSince1970: 1_000_000)
        let d2 = Date(timeIntervalSince1970: 1_010_000)
        let old = state(title: "Old title", slotId: slot, start: d1, end: d2)
        let new = state(title: "New title", slotId: slot, start: d1, end: d2)

        let (toEnd, toRequest) = LiveActivityPlanner.diff(
            existing: [(id: "act-1", state: old)],
            planned: [plannedItem(new)]
        )

        #expect(toEnd == ["act-1"])
        #expect(toRequest.map(\.state) == [new])
    }

    @Test("diff with empty plan ends everything")
    func diffEmptyPlan() {
        let s = state(
            title: "A", slotId: UUID(),
            start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 60))
        let (toEnd, toRequest) = LiveActivityPlanner.diff(
            existing: [(id: "act-1", state: s)], planned: [])
        #expect(toEnd == ["act-1"])
        #expect(toRequest.isEmpty)
    }
```

**Steps:**

- [ ] **Step 1:** Add the three tests; run
      `xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' -only-testing:WilgoTests/LiveActivityPlannerTests`
      Expected: FAIL to compile ("no member 'diff'").
- [ ] **Step 2:** Add `diff` to the planner; re-run. Expected: PASS (9 tests).
- [ ] **Step 3:** Commit:

```bash
git add Shared/Widget/LiveActivityPlanner.swift WilgoTests/Notifications/LiveActivityPlannerTests.swift
git commit -m "LiveActivityPlanner.diff: pure reconciliation of existing activities against the plan

#scheduledLA
tracking: https://www.notion.so/Change-LiveActivity-to-be-per-slot-3924b58e32c380c48a82de97a20cedd5"
```

---

### Phase 3 — ActivityKit shell + wiring

#### Commit 4 — Rewrite `LiveActivityRefresher.refresh` as the diff-driven reconciler

**Modify:** `Shared/Widget/LiveActivityRefresher.swift` — full new content:

```swift
import ActivityKit
import Foundation
import SwiftData

/// Reconciles the set of Wilgo Live Activities (live + pending-scheduled) against the pure plan
/// from `LiveActivityPlanner`.
///
/// Lives in `Shared/Widget` (compiled into both the app and the WidgetExtension targets) so that a
/// `LiveActivityIntent`'s `perform()` — which always runs in the **app process** — can drive the Live
/// Activity directly. The caller supplies the `ModelContext`: the app passes its `mainContext`; an
/// intent passes the context it already opened for its write.
///
/// Legal calling contexts for *requesting*: foreground, or a `LiveActivityIntent` `perform()`.
/// From the background (BGAppRefreshTask) requests throw `.visibility` and are swallowed — the BG
/// task degrades to a janitor that can still *end* stale cards. That is by design for this scope
/// (see documentation/ScheduledLiveActivity-implementation.md: BG work is deferred).
enum LiveActivityRefresher {
    @MainActor
    static func refresh(context: ModelContext, now: Date? = nil) async {
        let now = now ?? Time.now()
        let commitments = (try? context.fetch(.activeOnly)) ?? []
        let planned = LiveActivityPlanner.plan(commitments: commitments, now: now)

        let activities = Activity<NowAttributes>.activities
        let (toEnd, toRequest) = LiveActivityPlanner.diff(
            existing: activities.map { (id: $0.id, state: $0.content.state) },
            planned: planned
        )

        for activity in activities where toEnd.contains(activity.id) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        // Nearest-first so the scarce system queue (undocumented cap) is spent on the most
        // imminent occurrences; the first capacity error stops the loop — later occurrences
        // get queued on a future wake.
        for item in toRequest.sorted(by: { ($0.scheduledStart ?? now) < ($1.scheduledStart ?? now) }) {
            let content = ActivityContent(
                state: item.state,
                staleDate: item.staleDate,
                relevanceScore: item.relevanceScore
            )
            do {
                if let start = item.scheduledStart {
                    // Scheduled start: the system starts the card at `start` even if the app is
                    // dead by then. The alert configuration is mandatory for scheduled requests.
                    _ = try Activity.request(
                        attributes: NowAttributes(),
                        content: content,
                        pushType: nil,
                        style: .standard,
                        alertConfiguration: AlertConfiguration(
                            title: "\(item.state.commitmentTitle)",
                            body: "\(item.state.slotTimeText)",
                            sound: .default
                        ),
                        start: start
                    )
                } else {
                    _ = try Activity.request(
                        attributes: NowAttributes(),
                        content: content,
                        pushType: nil
                    )
                }
            } catch {
                // Capacity reached, activities disabled, or background-start attempt — in every
                // case, further requests would also fail this wake.
                print("LiveActivityRefresher.refresh() - request stopped: \(error)")
                break
            }
        }
    }
}
```

Note: `makeContentState(from:)` is deleted (superseded by `LiveActivityPlanner.makeState`); delete `staleDate(for:now:)` too.

**Modify:** `WilgoTests/Notifications/LiveActivityRefresherTests.swift` — delete the file. Its content-mapping coverage moved to `LiveActivityPlannerTests` (Commit 2); the ActivityKit shell is manual-verification territory (same policy as the old header comment).

**No call-site changes needed** — verify with `rg -n "LiveActivityRefresher.refresh|workAndScheduleNextBGTask" Wilgo Shared` that the paths are: `WilgoApp.onChange(scenePhase)` → `NowLiveActivityManager.workAndScheduleNextBGTask()` → `apply()` → `LiveActivityRefresher.refresh`, and `CheckInIntent`/`SnoozeIntent` → `CommitmentChangeRefresher.refreshAll()` → same. They all keep working unchanged; the BG-task registration also stays as-is per scope cut.

**Steps:**

- [ ] **Step 1:** Apply the rewrite + delete `LiveActivityRefresherTests.swift`.
- [ ] **Step 2:** Run the planner tests (nearest relatives of the change):
      `xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' -only-testing:WilgoTests/LiveActivityPlannerTests`
      Expected: PASS.
- [ ] **Step 3:** Full suite (per repo rule: only after targeted tests pass): `./test-with-cleanup.sh`
      Expected: PASS except the known pre-existing failure `CommitmentStageSnoozeTests/stageStatus_snoozeDoesNotAffectFutureOccurrence()`.
- [ ] **Step 4:** Commit:

```bash
git add Shared/Widget/LiveActivityRefresher.swift
git rm WilgoTests/Notifications/LiveActivityRefresherTests.swift
git commit -m "LiveActivityRefresher: reconcile scheduled per-occurrence Live Activities against the plan

Replaces the background-start design (impossible per ActivityKit) with iOS 26
scheduled starts, diffed on every app-process wake.

#scheduledLA
tracking: https://www.notion.so/Change-LiveActivity-to-be-per-slot-3924b58e32c380c48a82de97a20cedd5"
```

- [ ] **Step 5 — Manual verification (3Sauce, on simulator or device; REQUIRED before calling this done):**
  1. Create a commitment with a slot open now + a slot starting in ~5 minutes (second commitment).
  2. Foreground the app → card for the open slot appears immediately.
  3. Lock the device, wait past the second slot's start **without opening the app** → its card appears on time with the start alert (this is the scheduled start firing without the app).
  4. Tap **Done** on a card whose commitment has target 1 → that card disappears (goal met); others survive (per-occurrence independence).
  5. Tap **Done** on a card whose commitment has target ≥ 2 → the card stays and its count badge increments (e.g. 0/3 → 1/3; the reconcile re-bakes the count).
  6. Let a window end without checking in → card flips to the "Ended" stale look, buttons gone.
  7. Reopen the app → stale cards are removed (reconcile janitor).
  8. Edit a commitment title mid-window → card is recreated with the new title.
  9. Note the observed queue cap: how many pending cards exist after a fresh reconcile (`Activity<NowAttributes>.activities.count` via Xcode console, or count cards over a multi-slot day). Record it in the PRD page.

---

## Critical Files

| File                                                        | Role                                                         |
| ----------------------------------------------------------- | ------------------------------------------------------------ |
| `Shared/Widget/LiveActivityPlanner.swift` (new)             | Pure planning + diffing (all unit-tested logic)              |
| `Shared/Widget/LiveActivityRefresher.swift`                 | Thin ActivityKit reconciler shell                            |
| `Shared/Widget/NowAttributes.swift`                         | Per-occurrence `ContentState` (card identity + timer window) |
| `WidgetExtension/NowLiveActivity.swift`                     | Card UI: countdown, stale state, per-occurrence layout       |
| `Wilgo/Features/Notifications/NowLiveActivityManager.swift` | Untouched entry point (BG registration stays, per scope cut) |

### Dependency Graph

```
Commit 1: ContentState + card UI
    |
    +-- Commit 2: planner.plan   [parallel after 1]
    +-- Commit 3: planner.diff   [parallel after 1]
            |
            +-- Commit 4: refresher rewrite + manual verification [after 2 & 3]
```

Commits 2 and 3 are independent of each other (3 only shares the file with 2 — if run in parallel worktrees, rebase 3 on 2).

---

## Post-verification fixes (2026-07-06, from 3Sauce's on-device testing)

Manual verification found three defects. Root causes and fixes, one commit per bug:

### Bug 1 — Done blinks the card (end+recreate churn on count change)

The documented end+re-request-on-mismatch trade-off proved visibly annoying in practice. **Fix (Commit F1): in-place `update()` for *started* activities.** The diff gains an `ExistingActivity` input (`id`, `state`, `isPending` from `activityState == .pending`) and returns a `ReconcileActions` value with four buckets: exact match → keep; same firing (`slotId` + `windowStart`) with changed content **and started** → `toUpdate` (in-place, no blink; `update()` is legal even from background); pending with changed content → end+re-request (invisible, no churn cost); orphans → `toEnd`; unmatched planned → `toRequest`. This supersedes the "no update() path" decision — the reliability argument for end+recreate assumed the blink was rare, and `checkInCount` made it routine.

### Bug 2 — Card never returns after Done from the lock screen

Original hypothesis: the reconcile-serialization chain made `CheckInIntent.perform()` return before the reconcile ran, and ActivityKit's background-request grace applies only while the intent is executing — so the deferred `Activity.request` would throw `.visibility` after the old card had been ended. Proposed fix (F2): intents `await` the reconcile inside `perform()`.

**Verdict (on-device experiment, 2026-07-08): hypothesis REFUTED — F2 not landed.** With the app in confirmed `.background` (`didEnterBackground` logged ~50 s earlier, debugger attached), a lock-screen Snooze's intent-descended reconcile successfully executed a *scheduled* `Activity.request` well after `perform()` returned — no `.visibility` throw. On iOS 26.4, intent-descended background requests work. F2's implementation is parked in the git stash ("F2: intents await reconcile"); revisit only if unattached dogfood ever shows a vanished card after a lock-screen action. (Caveat: the experiment ran debugger-attached; that is the one untested variable.)

**Post-mortem — most probable actual cause of the original incident: the ended/dismissed-corpse bug fixed by G1** (`27d024c`). Pre-G1, the diff matched against *all* of `Activity.activities`: after Done ended the old card, its lingering `.dismissed` corpse matched the plan at every subsequent reconcile, so the replacement was never re-requested — explaining "never comes back, even on foreground," which visibility alone never could. (Saturation theory: to be closed by confirming the originally-affected commitment has no per-slot check-in cap.)

**Open anomaly (2026-07-08 09:07:28, under observation):** while the app was active and untouched, a started card was ended + re-requested (visible blink) although a same-printed-time occurrence of its slot was in the plan — an outcome the diff should not produce. A dedicated `end-diagnostic` log line now fires whenever it recurs (full-precision windows + differing state fields); diagnostics were converted to persisted `os.Logger` (subsystem "wilgo") so unattached dogfood runs stay readable via Console.app / `log collect`. Measured device queue cap: **5**.

### Bug 3 — Only one of several current cards shows (capacity hogging)

The plan queues the nearest `maxPlanned = 8` occurrences but the device cap is smaller (~5): matching far-future *pending* cards are kept by the diff, so current occurrences' requests hit `targetMaximumExceeded` and the break-on-error loop drops them — even on foreground. **Fix (Commit F3): capacity-aware eviction.** The diff additionally returns `keptPendings`; when a request throws `targetMaximumExceeded`/`globalMaximumExceeded`, the refresher ends the kept pending with the **latest** `windowStart` (only if later than the item being requested — evicting something more imminent would be self-defeating) and retries. Pending cards are invisible, so eviction has zero user-visible cost; most-imminent occurrences always win the queue. Non-capacity errors (`.visibility`, `.denied`) still break the loop.

---

## Known follow-ups (explicitly out of scope, tracked in the PRD)

- BG-task top-up / janitor improvements (deferred by 3Sauce until the foreground design is validated).
- Slot-start notification vs. scheduled-LA start-alert double-ding — evaluate in dogfood, then decide dedup.
- AlarmKit opt-in tier (separate plan).
- Merging identical-window cards (deferred; grouping-layer change only).
- Verify on-device that _pending_ activities expose `content.state` for diffing (Commit 4 manual step; fallback documented in Design Decisions).
- ~~In-place `update()` for started activities on content mismatch~~ — landed as fix F1 (started cards update in place). **Spike result (2026-07-07, on-device, iOS 26.x):** `update()` on a *pending* scheduled activity is **silently ignored** — no throw, no readback change (`activity.content` kept the old state after an awaited update), and the card started with the pre-update content. End+re-request is therefore the only correct path for pending content drift; do not revisit unless Apple documents update-on-pending support.
- BG-safety ordering for drifted pendings: the end runs before the re-request, so a reconcile in a request-illegal context (BG janitor) could end a drifted pending and fail to recreate it. Argued near-impossible today (every drift source is an in-app mutation that immediately reconciles in a request-legal context), but worth an ordering guard if BG work is ever built out.
