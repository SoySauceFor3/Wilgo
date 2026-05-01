# Sync Concepts — A Teaching Doc

**Audience:** 3Sauce (and future-3Sauce who has forgotten this).
**Purpose:** Build intuition for the offline-first sync pattern used in Phase 4 before reading the implementation plan. This is a *concepts* doc, not an implementation doc.
**Companion to:** [`./04-Sync.md`](./04-Sync.md) (the actual phase plan), [`./roadmap.md`](./roadmap.md).

> Why this doc exists: while planning Phase 4, the offline-first sync engine felt scary — distributed-systems-paper scary. After working through the pattern in detail, it turns out the *single-user* version of this problem is much narrower than the multi-writer problem those papers solve. This doc captures the explanation, the corner cases, and the mental model so we don't have to re-derive them next time.

---

## Why we picked the outbox pattern over alternatives

Briefly considered, briefly ruled out:

- **iCloud / `NSPersistentCloudKitContainer`** — Apple writes the sync engine, zero outbox code. But it has a *hard ceiling*: no server-side logic. Future payment/punishment features and server-initiated push notifications (reliable pill reminders that fire even when the app hasn't opened in days) are impossible. Migrating off CloudKit later is more painful than hand-rolling sync now.
- **PowerSync (or similar offline-sync library) on top of Supabase** — purpose-built for this exact problem, well-engineered. But the **Swift SDK is in open alpha** as of mid-2026, is a Kotlin SDK wrapped via SKIE (not native), has **no SwiftData integration**, and gives you a SQLite database — meaning we'd have to throw away or wrap our existing SwiftData layer. Bridging cost > outbox cost. Worth revisiting if it hits GA *and* gets SwiftData support.
- **Hand-rolled outbox + LWW + tombstones** (chosen) — the pattern shipped by WatermelonDB, PowerSync, and Supabase's own offline guides. Boring, well-understood, single-user-friendly. ~5 invariants to keep true.

---

## The core idea, in plain words

When the user mints a PositivityToken, two things must happen:

1. The local database (SwiftData) saves it. **Must be instant. Must work offline.**
2. The cloud (Supabase) eventually learns about it. **Can be slow. Can fail. Can retry.**

The naive approach is to do both at once. User taps save → app writes locally AND calls Supabase. If Supabase is down or the user is on a plane → the call fails → now what?

**The outbox is just this:** stop trying to do both at once. Split them in time.

> "I'll save locally now. I'll also write a sticky note that says 'tell the cloud about this later.' Some other process will read those sticky notes and act on them whenever the network is healthy."

The outbox is **a table of sticky notes**. Each row says "here's a pending change that needs to reach the cloud."

---

## The shape, concretely

Three pieces of code:

### Piece 1: An `OutboxEntry` SwiftData table

A to-do list, but for the network. Each row contains:

- `id` — unique ID of this sticky note
- `entity` — which table this is about, e.g. `"positivity_tokens"`
- `op` — `"upsert"` or `"delete"`
- `rowId` — the ID of the row being changed
- `payload` — the actual data, encoded as JSON bytes
- `createdAt` — when the sticky note was written (used for FIFO ordering)
- `attemptCount` — how many times we've tried to send this
- `lastError` — what went wrong on the last try (debugging)

### Piece 2: At every mutation site, also drop a sticky note

```swift
// User mints a positivity token
let token = PositivityToken(reason: "Showed up to the gym")
modelContext.insert(token)                                 // 1. local save
SyncEnqueue.upsert(token, userId: ..., in: modelContext)   // 2. write sticky note
dismiss()                                                  // 3. UI continues immediately
```

Both writes are **local SwiftData operations**. Synchronous, can't fail interestingly, don't talk to the network. The user's tap finishes in milliseconds. They could be on the moon.

### Piece 3: A background process (`SyncEngine`) drains the sticky notes

```
SyncEngine wakes up (app foreground / 30s timer / on-write)
  fetch all OutboxEntry rows, oldest first
  for each entry:
    try to send it to Supabase
    if it succeeded → delete the sticky note
    if it failed → bump attemptCount, save error, stop and try again later
```

That's the whole architecture. **The UI never waits on the engine, and the engine never blocks the UI.** They communicate through the outbox table.

---

## Why this shape (the design choices)

**Why a separate table instead of a "needs sync" flag on each row?**
A flag loses ordering and intermediate values when the user edits three times in a row. Worse: if the user *deletes* the row, the flag is gone with it; the cloud never learns about the delete. A separate outbox table preserves order *and* survives the deletion of the row it's about.

**Why store JSON bytes in `payload` instead of just the row ID?**
If we re-fetched at send time, we'd be sending the row's *current* state, not the state at the moment the user made the change. Encoding the snapshot at enqueue time means each sticky note represents *that specific change*.

**Why does the engine halt on the first failure instead of plowing ahead?**
Foreign keys. If the outbox has `[Commitment-upsert, CheckIn-upsert]` and Commitment fails transiently, plowing ahead to CheckIn would fail too — the cloud has no Commitment to attach the CheckIn to. **Halting on first failure preserves causal order.** Next attempt: Commitment goes, then CheckIn goes.

---

## Corner cases, as stories

### Story 1: User is on a plane

Tap save → SwiftData insert succeeds → sticky note written → UI dismisses.

SyncEngine wakes 30s later, push throws "no network." Catch block bumps `attemptCount` to 1, stores error, **stops the loop.** Sticky note stays.

Plane lands, WiFi reconnects. SyncEngine wakes on next foreground or timer. Sticky note is still there. Call succeeds. Sticky note deleted. **No data lost. No user action required.**

### Story 2: Network drops mid-request

Two cases:

- **Server never received it** → throws → sticky note stays → retry next round. Fine.
- **Server received it but app didn't get the response** → server has the row, sticky note also stays → retry next round → server sees the same row come in.

Why this is OK: the operation is `upsert` (insert-or-update by primary key), not `insert`. **Sending the same upsert twice with the same `id` is idempotent** — second time is a no-op. We don't try to figure out "did the server receive it"; we design the operation so the answer doesn't matter.

### Story 3: Server rejects the request (RLS, schema mismatch)

Different from network error. Network errors are transient — retry helps. Server rejections are *permanent* — retrying forever is just spam.

Phase 4's current design doesn't distinguish: it bumps `attemptCount` and retries. Known sharp edge. Fix is straightforward — after a threshold (e.g. `attemptCount > 5` *and* the error is a 4xx), stop retrying and surface the entry to a "needs human attention" state. We don't need this on day 1; we need to *notice* it. The `lastError` field is what makes this debuggable.

### Story 4: App force-killed mid-sync

Tap save → sticky note written → SyncEngine starts uploading → user force-quits.

Both writes (the row and the sticky note) committed to SwiftData *before* the upload started. Force-quit doesn't undo SwiftData. Next launch, SyncEngine finds the sticky note, retries. Same idempotency story as Story 2.

The invariant: **the sticky note is written in the same transaction as the local change.** They both make it to disk, or neither does. Crashing between them yields neither change nor sticky note — equivalent to "user never tapped save."

### Story 5: User makes 3 rapid edits before any sync

Three sticky notes pile up: A, B, C. Network is fine.

Engine processes in order. A → server now has A. B → server overwrites with B. C → server overwrites with C. Final cloud state matches final local state. ✅

**Bonus subtlety:** all three target the same `rowId`. We could compress them ("just send the latest"). The current design doesn't — sends all three. Slightly wasteful, much simpler, negligible bandwidth on a single-user app. Optimization to know about, not to ship.

### Story 6: Two devices both edit the same row while offline

Phone edits at 10:00am. iPad edits the same row at 10:05am. Both offline.

**Sub-case 6a: Phone reconnects first.**
- Phone's sticky note pushes → server stamps `updated_at = (server's time, e.g. 10:30)`. Cloud has phone's version.
- iPad reconnects later → iPad's sticky note pushes → server overwrites with iPad's version, `updated_at = 10:35`.
- When phone next pulls, it gets iPad's version. **Final state: iPad wins.**

**Sub-case 6b: iPad reconnects first.**
- iPad's sticky note pushes → cloud has iPad's version, `updated_at = 10:30`.
- Phone reconnects → phone's sticky note pushes → server **accepts it** (RLS only checks "is this your row?", not "is your version newer"). Cloud overwrites with phone's version, `updated_at = 10:35`.
- When iPad next pulls, it gets phone's version. **Final state: phone wins.**

**The crucial takeaway:** "last write wins" really means **whichever sticky note hits the server last wins** — not whichever edit was made later in wall-clock time. The system doesn't preserve "true" intent. It preserves the last push.

For a single-user app, this is fine — the human is one human, not racing themselves. If we ever needed edit-time semantics, we'd need timestamps stamped at edit time plus per-row conflict logic — the rabbit hole that leads to the scary papers. Explicitly not going there.

### Story 7: User deletes a row

Hard delete is dangerous: another offline device pushes the row back as new on next sync, resurrecting it.

Solution: **soft delete.** "Deleting" sets `deleted_at = NOW()`. The sticky note is an `upsert` with that field set. Other devices pull the row, see `deleted_at` is non-null, remove their local copy. **Tombstones** are how you tell other devices "this is dead, stay dead."

Every UI fetch site adds `WHERE deleted_at IS NULL`. This benefits from a centralized fetch helper rather than scattering the filter.

### Story 8: Pull fetches a row the user is currently editing

Edge case, single-user, low-probability.

**Scenario:** Cloud has commitment titled "Run 5k". User edits to "Run 10k" on phone. SwiftData updated locally; sticky note in outbox; sync hasn't drained yet. Then a pull runs.

**Without protection:** the pull asks "give me anything updated since my last pull" → server returns the row with title="Run 5k" → pull overwrites local. The user's "Run 10k" *disappears from the UI* until the push half drains and the next pull catches up. Eventually correct, but ugly flicker.

**With the skip-pending rule:** before applying a pulled row, check "do I have a pending sticky note for this `rowId`?" Yes → skip this row in the pull. The push half will reconcile it shortly.

In code:

```swift
let pendingRowIds = fetchOutboxRowIds()
for serverRow in pulledRows where !pendingRowIds.contains(serverRow.id) {
    applyToLocal(serverRow)
}
```

Not needed in Phase 4 — eventual state is correct either way. Quality-of-life fix to add if the flicker actually appears in practice.

### Story 9: Outbox grows huge (engine broken or paused)

Memory is fine — sticky notes are on disk, not in RAM. Storage is fine — even thousands of small entries are kilobytes. The risk is the *first* sticky note has a permanent error (Story 3) and is **blocking everyone behind it** because of halt-on-fail.

Exactly why `attemptCount` and `lastError` exist, and why we need the "give up after N permanent errors" rule. The engine's job is to make the queue *eventually drain*; permanent failures must be surfaced rather than silently retried forever.

---

## The other half: pulling from cloud → local

The push side is the outbox. The pull side is its own thing, and it's actually simpler.

### The setup

Every synced row has a server-stamped `updated_at`, updated automatically on every write (Postgres trigger, written once in the migration). The app stores **`lastPulledAt`** — the high-water mark of "I've already seen everything up to this moment."

### The pull loop

```
Ask Supabase: "Give me all rows from positivity_tokens
              where updated_at > lastPulledAt"

For each row that comes back:
  if local has this row (by id) → overwrite local fields
  else if it's a tombstone (deleted_at != null) → delete local
  else → insert into local

Update lastPulledAt to the server's clock.
```

That's the entire algorithm. **No outbox on this side, no retries, no ordering.** A pull is just "give me the diff since I last looked," apply it, remember when you looked.

### Why the pull is simpler than the push

- **Idempotency is free.** Re-running the same pull just re-applies the same overwrites. No state corrupted.
- **No ordering problem.** The server tells us what changed; we don't have to schedule anything.
- **Failure is cheap.** Network drops mid-pull → we don't update `lastPulledAt` → next pull asks the same question and gets the same data again. No loss.

### Three details that matter

**1. `lastPulledAt` uses the server's clock, not the client's.**
If we wrote `lastPulledAt = Date()` at the end of a pull, we'd be using *my phone's* clock to ask *the server's* database a question. If my phone is 30s slow, we'd skip 30s of changes on the next pull. Forever. Solution: the server returns "here's the timestamp at which I served this query"; save *that* as `lastPulledAt`.

**2. Tombstones (`deleted_at`) are how the pull learns about deletions.**
The cloud doesn't `DELETE FROM`. It sets `deleted_at = NOW()`. From the pull's perspective, a deletion is just "an update where `deleted_at` is now non-null." Without tombstones, **deletions are invisible to other devices** — the row stops appearing in queries, but the pull has no way to learn.

**3. When does the pull run?**
Same triggers as the push: app foreground, 30s timer while active, after a successful push. Phase 4's design is `push then pull` so the user's own changes go up before pulling someone else's down. Order doesn't matter for correctness; it just feels natural.

---

## Sync frequency — the knobs

Phase 4 ships with three triggers:

1. **App foreground** — every time the user opens the app or returns from background.
2. **Periodic timer** — every **30 seconds** while in the foreground.
3. **On-write push** — after the outbox grows, kick off a push opportunistically.

**No background sync (BGTask) yet.** The app only syncs while the user has it open.

### Why 30s?

| Frequency | Battery | Bandwidth | Multi-device freshness            |
|-----------|---------|-----------|-----------------------------------|
| 5s        | bad     | wasteful  | great                             |
| 30s       | fine    | tiny      | fine for single-user              |
| 5min      | great   | minimal   | feels stale on second device      |

For a single-user app where multi-device sync is "nice to have," not a real-time feature, 30s is the standard sweet spot. WatermelonDB and PowerSync default in this range.

### Effective frequency in real usage

- **Open app → up-to-date within ~1s** (foreground push+pull on launch)
- **Make an edit → cloud knows within ~1s** (on-write push)
- **Edit on device A → device B sees it next time it foregrounds** (B isn't running)
- **Both devices open → they converge within 30s of each other**

The user almost never waits the full 30s. The timer is a safety net.

### What we are NOT doing, and why

- **No BGTask background sync.** iOS only grants background time opportunistically (charging, WiFi, idle), and it's annoying to test. Skipping means "online when open, dormant when closed." Acceptable for v1.
- **No realtime websockets.** Supabase Realtime is for live multi-user collaboration; single-user apps don't need it. Adds complexity, drains battery.
- **No exponential backoff** in current Phase 4 doc. If a push fails it retries on the next 30s tick. Fine when failures are "user is on a plane" (binary offline → online), not "server is degraded." Worth adding if we hit a flaky-server era.

---

## The ~5 sync invariants (the "things that must stay true")

These are what make the system correct. Each Phase 4 commit should preserve them, and we should test for them by name.

1. **Local change + sticky note are written in the same SwiftData transaction.** Crash between them = neither happens.
2. **Outbox processes in insertion order** (FIFO by `createdAt`). FK parents before children.
3. **Push halts on first failure.** Don't poison later entries with "the row I depend on isn't on the server yet."
4. **All cloud operations are idempotent** (`upsert` by primary key, not `insert`). Replay is safe.
5. **`lastPulledAt` uses the server's clock, not the client's.** Returned by the pull endpoint, not `Date()`.

Two more that aren't strictly invariants but are easy to break:

6. **Every UI fetch filters `WHERE deleted_at IS NULL`.** Centralize this; don't sprinkle.
7. **RLS policies have integration tests** that assert User A cannot see User B's rows. Don't trust eyeballing — silent allow-all bugs are the worst failure mode.

---

## The mental model to take away

Three sentences:

1. **Local writes are immediate; cloud writes are eventual.** The outbox is the buffer between them.
2. **The sticky note IS the source of truth for "the cloud needs to know this."** Not a flag, not memory state, not a callback — a row in a SwiftData table that survives crashes.
3. **Retry + idempotent operations + ordered draining = correct under almost any failure.** Network glitches, force-quits, and replays all collapse to "same sticky note tried again later."

The reason this pattern feels intimidating but is actually mundane: each individual rule is simple, but a few invariants must stay true *together*. The list above turns "silent corruption fear" into "concrete things to verify."

The scary distributed-systems papers (Bayou, Dynamo, vector clocks, CRDTs) solve the **multi-writer concurrent-edit** problem. Wilgo is **single-user, single-writer-at-a-time, append-heavy data**. ~90% of paper-scary complexity does not apply.
