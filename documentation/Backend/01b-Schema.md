# Phase 1b — Real Schema + RLS

**PRD:** [Backend (Notion)](https://www.notion.so/Backend-34a4b58e32c3808dbb2be218a09e73cd)
**Tracking:** TBD (3Sauce will paste a Notion sub-page URL before implementation begins)
**Tag:** `#backendSchema1b`

> Roadmap: [README.md](./README.md). Prerequisite: [01a-Spike.md](./01a-Spike.md) must be merged first.

---

## Status

**Stub.** This file captures the TODO list and locked decisions. The detailed commit plan will be filled in once Phase 1a is merged and we've learned what the SDK actually feels like. We don't want to over-design before that learning lands.

---

## Context

Phase 1a proved we can talk to Supabase. Phase 1b builds the real, multi-table schema that mirrors our SwiftData models, plus the RLS policies that make the database safe for multiple users to share. No SyncEngine yet — that's Phase 4. No auth integration yet — Phase 2 fills `auth.uid()` in for real. Phase 1b's RLS tests use seeded `auth.users` rows.

What stays out of Phase 1b (deferred to Phase 4):
- `updated_at` / `deleted_at` columns and triggers.
- `(user_id, updated_at)` composite indexes.
- Tombstone purge logic.

---

## Locked decisions

### Schema overview — 7 tables

| Swift model | Postgres | Why this shape |
|---|---|---|
| `Commitment` | table `commitments` | top-level entity |
| `Slot` | table `slots` | child with own lifecycle (created/edited/deleted independently) |
| `Tag` | table `tags` | independent entity |
| `Commitment.tags` ↔ `Tag.commitments` | join table `commitment_tags` | many-to-many; can't be a column |
| `CheckIn` | table `check_ins` | append-shaped event (insert + delete only, no updates) |
| `SlotSnooze` | table `slot_snoozes` | append-shaped event |
| `PositivityToken` | table `positivity_tokens` | top-level entity, mutable status |
| `Cycle` (struct) | JSONB column on `commitments.cycle` | value type, no identity, only meaningful inside Commitment |
| `GracePeriod` (struct) | JSONB column on `commitments.grace_periods` | value-type array |
| `Target` (`QuantifiedCycle`) | JSONB column on `commitments.target` | value type |

Rule of thumb: **a model gets its own table only if it has identity (own ID + lifecycle) or is queried independently.** Cycle/Target/GracePeriod fail both tests.

### Why JSONB for value-type structs

- Round-trips through `JSONEncoder`/`JSONDecoder` in one shot — keeps the sync mapper simple.
- No artificial join tables; no JOINs on every Commitment fetch.
- Editing a commitment's cycle is a single-row update, not a multi-table transaction.

Flat columns (`cycle_kind`, `cycle_reference`, ...) would work for `Cycle` but not for `GracePeriod` (which is an array). Picking JSONB uniformly keeps the encoding logic consistent.

### Slot recurrence — Postgres arrays, not JSONB

`recurrence_kind TEXT`, `active_weekdays SMALLINT[]`, `active_month_days SMALLINT[]`. Flat list of integers, no nesting; Postgres arrays are queryable if we ever need them.

### Identity & RLS

- `id UUID PRIMARY KEY` on every table. Client-generated, matching SwiftData's `@Attribute(.unique) var id: UUID`. Never auto-increment.
- `user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE` on every synced table.
- RLS policy pattern (per table):
  ```sql
  ALTER TABLE <t> ENABLE ROW LEVEL SECURITY;
  CREATE POLICY "<t>_select_own" ON <t> FOR SELECT USING (user_id = auth.uid());
  CREATE POLICY "<t>_insert_own" ON <t> FOR INSERT WITH CHECK (user_id = auth.uid());
  CREATE POLICY "<t>_update_own" ON <t> FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
  CREATE POLICY "<t>_delete_own" ON <t> FOR DELETE USING (user_id = auth.uid());
  ```

### FK + cascade

| SwiftData side | Postgres |
|---|---|
| `Slot.commitment` (cascade) | `slots.commitment_id` FK with `ON DELETE CASCADE` |
| `CheckIn.commitment` (cascade) | `check_ins.commitment_id` FK with `ON DELETE CASCADE` |
| `SlotSnooze.slot` (cascade) | `slot_snoozes.slot_id` FK with `ON DELETE CASCADE` |
| `Commitment` ↔ `Tag` (nullify) | `commitment_tags` join row deleted when either side is deleted |

Server-side cascades are for hard-delete admin work. Sync-time deletes will be soft-deletes via `deleted_at` once Phase 4 lands.

### Append-shaped tables

`check_ins`, `slot_snoozes` accept inserts and deletes from the client; no updates. Phase 4 layers tombstones over the deletes.

### Migrations are SQL files in the repo

Schema lives under `supabase/migrations/`. No dashboard clicking. Every schema change is a reviewable migration file.

---

## TODOs (to expand into a commit plan once Phase 1a is merged)

### Pre-work (TODO during Phase 1a or right after)
- [ ] Read the `supabase-swift` SDK README and find its idiomatic encode/decode patterns for: insert, select-by-id, batch insert, joined select.
- [ ] Decide on the Swift "DTO" layer: do `@Model` SwiftData classes encode/decode directly, or do we add a parallel `CommitmentDTO: Codable` for transport? (Probably parallel DTOs — `@Model` types have SwiftData baggage that doesn't serialize cleanly.)
- [ ] Confirm Supabase's RLS test harness (`supabase test db` + pgTAP) is set up.

### Schema migrations (one commit per table or pair)
- [ ] Drop `commitments_spike` from Phase 1a.
- [ ] `commitments` — id, user_id, title, created_at, cycle JSONB, target JSONB, grace_periods JSONB, encouragements JSONB, proof_of_work_type TEXT, punishment TEXT NULL, is_reminders_enabled BOOL, RLS.
- [ ] `tags` — id, user_id, name, display_order, created_at, RLS.
- [ ] `commitment_tags` — composite PK (commitment_id, tag_id), user_id, FK cascades, RLS.
- [ ] `slots` — id, user_id, commitment_id (FK cascade), start, end, recurrence_kind, active_weekdays, active_month_days, RLS.
- [ ] `check_ins` — id, user_id, commitment_id (FK cascade), status, created_at, psych_day, source, RLS.
- [ ] `slot_snoozes` — id, user_id, slot_id (FK cascade), psych_day, snoozed_at, RLS.
- [ ] `positivity_tokens` — id, user_id, reason, created_at, status, day_of_status NULL, RLS.

### Verification
- [ ] RLS isolation tests: User A's writes are invisible to User B for SELECT/INSERT/UPDATE/DELETE on every table.
- [ ] Round-trip test (replacing the spike one): `Commitment` Swift DTO → insert → select → decode → assert equal across all fields including JSONB.
- [ ] Round-trip test for FK cascades: deleting a commitment row deletes its slots, check-ins, slot_snoozes, and commitment_tags entries server-side.

### Cleanup of Phase 1a artifacts
- [ ] Drop `commitments_spike` table.
- [ ] Remove the `#if DEBUG` "Spike: Insert + Read" button from `SettingsView.swift`.
- [ ] Remove `SupabaseSpikeTests.swift`.
- [ ] Keep: `Backend.client` singleton, `Supabase.local.xcconfig`, the SDK dependency.

---

## Open questions to resolve during Phase 1b

- Where does `proof_of_work_type` go — TEXT enum column, or part of a JSONB blob? (Currently leaning TEXT, since it's a simple flat enum.)
- What does the RLS test harness file layout look like — one big `tests.sql` or per-table?
- Do we need any indexes in Phase 1b (beyond PKs and FKs)? Probably not — query patterns are unclear until Phase 4 wants delta-pull. Defer.
- How do we handle `auth.users` seeding in tests (since Phase 2 hasn't real-wired SIWA yet)? Likely: insert directly via service-role key in the test setup.

---

## Verification (placeholder)

Will be filled in alongside the commit plan. Skeleton:

1. `supabase db push` applies all Phase 1b migrations cleanly on the dev project.
2. `supabase test db` passes — RLS isolation holds for all tables.
3. `./test-with-cleanup.sh` passes; new round-trip test covers a real `Commitment` DTO.
4. Manual: open dashboard, see all 7 tables with RLS lock icons.
5. Spike artifacts are gone (table dropped, button + test removed).
