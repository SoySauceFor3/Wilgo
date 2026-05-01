# Phase 4 — Sync Engine (PT as the template)

**PRD:** [Backend (Notion)](https://www.notion.so/Backend-34a4b58e32c3808dbb2be218a09e73cd)
**Tracking:** _TBD — 3Sauce will create a Phase 4 Notion sub-page._
**Tag:** `#backendSyncPT` for this phase. Subsequent entity phases use `#backendSync<Entity>` (e.g. `#backendSyncTag`).
**Roadmap link:** [`./roadmap.md`](./roadmap.md)
**Depends on:** Phase 1b (`positivity_tokens` table + DTO) ✅, Phase 2 (auth — supplies `userId`).

> This phase builds the **full sync route** end-to-end on a single entity: `PositivityToken`.
> Everything here — the outbox model, the engine, the call-site enqueue pattern, the conflict columns, the RLS sweep — becomes the **template** for the remaining six entities (Tag, Commitment, Slot, CheckIn, SlotSnooze, Cycle/GracePeriod).
>
> The roadmap originally bundled "schema for everything → engine for everything." We re-sliced because doing one entity end-to-end surfaces every real unknown (auth wiring, outbox semantics, retry, ordering, RLS) on the simplest table — one column-flat, no FKs, no JSONB, no joins. The other six entities then become mechanical.

---

## Context

Phase 1b proved the wire format: a `PositivityTokenDTO` can round-trip through Supabase. But **the app does not use it yet**. The two real call sites (`AddPositivityTokenView.saveToken()` and `PositivityTokenCompensator.apply`) still only touch SwiftData; nothing reaches the cloud.

This phase wires those sites — and any future PT mutation site — to the cloud, **without giving up offline-first**. The user must still be able to mint a token on a plane and have it sync later, transparently. The UI never awaits the network.

---

## Architecture Summary

```
┌─────────────────────────────────────┐
│ Mutation site (e.g. saveToken)      │
│  1. modelContext.insert(token)      │
│  2. modelContext.insert(OutboxEntry)│ ← synchronous, local-only
│  3. dismiss()                        │
└──────────────┬──────────────────────┘
               │
               ▼ (later, async, opportunistic)
┌─────────────────────────────────────┐
│ SyncEngine                           │
│  • drains OutboxEntry FIFO          │
│  • POSTs DTO to Supabase            │
│  • on success: delete OutboxEntry   │
│  • on failure: bump attemptCount,   │
│    retry with backoff               │
│  • periodically pulls server rows   │
│    where updated_at > lastPulledAt  │
└─────────────────────────────────────┘
```

Three new pieces:

1. **`OutboxEntry`** — a SwiftData model representing one pending write.
2. **`SyncEngine`** — an `actor` that owns push/pull for all synced entities. PT-only in this phase; gains entity registrations later.
3. **`updated_at` + `deleted_at` columns** added to `positivity_tokens`, plus RLS policies (now that Phase 2 exists, `auth.uid()` is real).

---

## Design Decisions

### 1. Outbox vs alternatives

**Decision:** explicit `OutboxEntry` SwiftData table, manual enqueue at every mutation site.

**Why not a per-row "dirty flag"?** Loses ordering (FK parents must push before children), can't represent deletes (the row is gone), can't represent multiple distinct edits before sync.

**Why not fire-and-await on every write?** Not offline-first. Plane mode = broken UI.

**Why not a SwiftData `didSave` observer that auto-enqueues?** Magic — hard to debug, hard to opt out (e.g., draft state you don't want synced). Also still needs an outbox table underneath; this is style, not structure. We may revisit later if the explicit calls become repetitive across all 7 entities.

**Why not a CRDT / event log?** Massively over-engineered for a single-user LWW app. Roadmap rules it out.

The explicit-outbox pattern is what WatermelonDB and PowerSync use; the roadmap already cites them.

### 2. Conflict resolution

**Decision:** row-level last-write-wins. Server stamps `updated_at` on every accepted write (via Postgres trigger). On pull, server `updated_at` always overwrites local.

**Why not per-field merge / HLC?** Single-user app — true concurrent edits to the same row are vanishingly rare. Roadmap §"Sync & Conflict Model" already locked this in.

### 3. Soft delete via `deleted_at`

**Decision:** deletes set `deleted_at = NOW()` instead of `DELETE FROM`. UI filters `WHERE deleted_at IS NULL` everywhere; sync uses tombstones so other devices learn about deletions.

**Why not hard delete?** A second device that's been offline for a week would resurrect deleted rows on next push if there's no tombstone.

**Tombstone purge window:** 60–90 days (handled in a future cleanup job, not this phase). Devices offline longer must do a full resync — acceptable.

### 4. RLS turned on in this phase

**Decision:** add RLS policies to `positivity_tokens` as part of this phase, gated by `auth.uid() = user_id`. Phase 1b deliberately skipped RLS because auth didn't exist yet.

**Why now?** Phase 2 has wired `auth.uid()`. Turning on RLS without integration tests is dangerous (silent allow-all bugs). This phase has the integration tests anyway, so add RLS while the test harness is open.

### 5. Engine ownership

**Decision:** `SyncEngine` is an `actor` (Swift concurrency), one app-wide instance, started at launch. Triggers: app foreground, on-write outbox grew, periodic timer (30s) when foreground.

**Why an actor?** Push/pull operations need serialization (don't pull while pushing the same entity), and actors give us that without a manual lock. Also fits cleanly with `async`/`await` SDK calls.

**Why not BGTask / background sync?** Out of scope here. We can add it later without changing the engine's contract — BGTask just becomes another trigger.

### 6. PT-only in this phase

**Decision:** the engine knows how to handle exactly one entity (`PositivityToken`) at end of this phase. Adding Tag, Commitment, etc. happens in **separate phases** (`04a-Tag.md`, `04b-Commitment.md`, …), each of which is mostly: register a new `EntitySyncer<T>`, write the round-trip + outbox tests, modify mutation sites.

**Why not generalize now?** Premature. The entity registration shape will be obvious only after PT works end-to-end. Generalize on the second entity, not the first.

---

## Major Model Changes

| Entity                                                     | Change                                                                                                          |
| ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| **New:** `Shared/Sync/OutboxEntry.swift`                   | New `@Model` for pending writes                                                                                 |
| **New:** `Shared/Sync/SyncEngine.swift`                    | Actor that drains the outbox + pulls server rows                                                                |
| **New:** `Shared/Sync/SyncEnqueue.swift`                   | Tiny helper: `OutboxEntry.upsert(_:userId:context:)` + `.delete(_:userId:context:)`. Keeps call sites readable. |
| `Shared/Models/PositivityToken.swift`                      | No structural change. Confirm `id: UUID` is stable across edits.                                                |
| `Shared/Backend/PositivityTokenDTO.swift`                  | Add `updatedAt: Date` + `deletedAt: Date?` fields + `CodingKeys`.                                               |
| `Wilgo/Features/PositivityToken/AddView.swift`             | After `modelContext.insert(token)`, call `OutboxEntry.upsert(token, ...)`.                                      |
| `Wilgo/Features/Commitments/.../PositivityTokenCompensator.swift` | Accept `ModelContext` parameter; after each `token.status = .used`, enqueue.                            |
| **New migration:** `supabase/migrations/0003_positivity_tokens_sync.sql` | Add `updated_at`, `deleted_at`, trigger to bump `updated_at`, enable RLS.                          |
| `Wilgo/WilgoApp.swift`                                     | Register `OutboxEntry.self` in schema; start `SyncEngine` at launch.                                            |

---

## Commit Plan

### Phase 4-PT — PT end-to-end

The goal is one entity (`PositivityToken`) that survives offline use, syncs on reconnect, deduplicates, and respects RLS. This phase has 6 commits.

#### Commit 1 — add `updated_at`/`deleted_at` to `positivity_tokens` + RLS

**Create:** `supabase/migrations/0003_positivity_tokens_sync.sql`

```sql
ALTER TABLE public.positivity_tokens
  ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN deleted_at TIMESTAMPTZ NULL;

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER positivity_tokens_set_updated_at
  BEFORE UPDATE ON public.positivity_tokens
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- RLS
ALTER TABLE public.positivity_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users see own rows"
  ON public.positivity_tokens FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "users insert own rows"
  ON public.positivity_tokens FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "users update own rows"
  ON public.positivity_tokens FOR UPDATE
  USING (auth.uid() = user_id);
```

Note: no DELETE policy — we soft-delete via UPDATE.

**Modify:** `Shared/Backend/PositivityTokenDTO.swift` — add `updatedAt` and `deletedAt` fields with snake_case `CodingKeys`.

**Modify:** `WilgoTests/Backend/PositivityTokenRoundTripTests.swift` — assert `updated_at` is server-stamped (i.e., not equal to whatever we sent).

**Manual verification:** push migration to dev Supabase. In dashboard, confirm column + trigger + 3 policies exist.

#### Commit 2 — `OutboxEntry` model + tests

**Create:** `Shared/Sync/OutboxEntry.swift`

```swift
@Model final class OutboxEntry {
    @Attribute(.unique) var id: UUID
    var entity: String        // "positivity_tokens"
    var op: String            // "upsert" | "delete"
    var rowId: UUID
    var payload: Data         // encoded DTO; empty for delete
    var createdAt: Date
    var attemptCount: Int
    var lastError: String?

    init(entity: String, op: String, rowId: UUID, payload: Data) {
        self.id = UUID()
        self.entity = entity
        self.op = op
        self.rowId = rowId
        self.payload = payload
        self.createdAt = Date()
        self.attemptCount = 0
    }
}
```

**Modify:** `Wilgo/WilgoApp.swift` — add `OutboxEntry.self` to schema.

**Create:** `WilgoTests/Sync/OutboxEntryModelTests.swift` — persist, fetch in FIFO, mutate `attemptCount`.

#### Commit 3 — `SyncEnqueue` helper + modify call sites (no engine yet)

**Create:** `Shared/Sync/SyncEnqueue.swift`

```swift
enum SyncEnqueue {
    static func upsert(_ token: PositivityToken, userId: UUID, in ctx: ModelContext) {
        let dto = PositivityTokenDTO(token, userId: userId)
        let payload = try! JSONEncoder.snake.encode(dto)
        ctx.insert(OutboxEntry(entity: "positivity_tokens", op: "upsert", rowId: token.id, payload: payload))
    }
    static func delete(_ token: PositivityToken, userId: UUID, in ctx: ModelContext) {
        ctx.insert(OutboxEntry(entity: "positivity_tokens", op: "delete", rowId: token.id, payload: Data()))
    }
}
```

**Modify:** `Wilgo/Features/PositivityToken/AddView.swift`:

```swift
private func saveToken() {
    let token = PositivityToken(reason: trimmedReason)
    modelContext.insert(token)
    SyncEnqueue.upsert(token, userId: currentUserId, in: modelContext)
    dismiss()
}
```

**Modify:** `Wilgo/Features/Commitments/FinishedCycleReport/PositivityTokenCompensator.swift` — accept `ModelContext`; after each `token.status = .used` block, call `SyncEnqueue.upsert(token, ...)`.

**Create:** `WilgoTests/Sync/PositivityTokenEnqueueTests.swift` — minting a token enqueues one upsert; compensating N tokens enqueues N upserts; payload decodes back to the same DTO.

This commit is fully testable without any network — the engine doesn't exist yet, but enqueue is verified.

#### Commit 4 — `SyncEngine` push (drain outbox)

**Create:** `Shared/Sync/SyncEngine.swift`

```swift
actor SyncEngine {
    func push(context: ModelContext) async {
        let entries = try? context.fetch(
            FetchDescriptor<OutboxEntry>(sortBy: [SortDescriptor(\.createdAt)])
        )
        for entry in entries ?? [] {
            do {
                switch entry.op {
                case "upsert":
                    try await Backend.client.from(entry.entity)
                        .upsert(JSONSerialization.jsonObject(with: entry.payload) as! [String: Any])
                        .execute()
                case "delete":
                    try await Backend.client.from(entry.entity)
                        .update(["deleted_at": Date()])
                        .eq("id", value: entry.rowId)
                        .execute()
                default: continue
                }
                context.delete(entry)
            } catch {
                entry.attemptCount += 1
                entry.lastError = String(describing: error)
                break // halt on first failure to preserve order
            }
        }
        try? context.save()
    }
}
```

**Create:** `WilgoTests/Sync/SyncEnginePushTests.swift` — enqueue 3 PT mutations → call `push` → assert all 3 rows exist on server, outbox is empty.

#### Commit 5 — `SyncEngine` pull

**Modify:** `Shared/Sync/SyncEngine.swift` — add `pull(context:)` that fetches `positivity_tokens WHERE updated_at > lastPulledAt`, upserts/deletes locally, advances `lastPulledAt` to server clock.

Persist `lastPulledAt` per entity in `UserDefaults` (good enough for now; if we need atomicity later, move it into the SwiftData store).

**Create:** `WilgoTests/Sync/SyncEnginePullTests.swift` — server has 2 PT rows with later `updated_at` → call `pull` → both appear locally with correct fields.

#### Commit 6 — wire engine into app lifecycle

**Modify:** `Wilgo/WilgoApp.swift` — instantiate `SyncEngine`, run `push` + `pull` on `.scenePhase == .active`, plus a 30s timer while active.

**Manual verification (critical):**
1. On simulator, mint 3 tokens **with WiFi off**. Verify outbox grows in SwiftData inspector.
2. Turn WiFi on. Within 30s, verify all 3 rows in Supabase dashboard, outbox is empty.
3. Edit a token's `status` in the dashboard directly. Wait 30s. Verify local state reflects the change.
4. Sign in with the same Apple ID on a second simulator. Verify all PT data appears.
5. Data-loss drill: delete app, reinstall, sign in. Verify all PT data restored from server.

---

## Critical Files

| File                                           | Role                                           |
| ---------------------------------------------- | ---------------------------------------------- |
| `Shared/Sync/OutboxEntry.swift` (new)          | Pending-write queue model                      |
| `Shared/Sync/SyncEngine.swift` (new)           | Push + pull actor                              |
| `Shared/Sync/SyncEnqueue.swift` (new)          | Call-site helper to make enqueue readable      |
| `supabase/migrations/0003_positivity_tokens_sync.sql` | Conflict columns + RLS                  |
| `Wilgo/Features/PositivityToken/AddView.swift` | First real mutation site to use the outbox    |
| `Wilgo/Features/Commitments/FinishedCycleReport/PositivityTokenCompensator.swift` | Second mutation site |

### Dependency Graph

```
Commit 1 (migration + DTO fields)
    │
    ├── Commit 2 (OutboxEntry)         [parallel]
    │       │
    │       └── Commit 3 (enqueue + call sites)
    │               │
    │               ├── Commit 4 (engine push)
    │               │       │
    │               │       └── Commit 5 (engine pull)
    │               │               │
    │               │               └── Commit 6 (wire into lifecycle)
```

---

## Out of Scope (handled later)

- BGTask-driven background sync — current scope is foreground + timer.
- Tombstone garbage collection — needs a separate cron / Edge Function.
- Generalizing `SyncEngine` to register arbitrary entities — happens organically in `04a-Tag.md` (the second entity exposes the right shape).
- Conflict UI / per-field merge — explicitly out of scope per roadmap.
- Migration of existing local PT history into Supabase on first sign-in — that's Phase 3.
