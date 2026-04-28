# Backend — Master Roadmap

**PRD:** [Backend (Notion)](https://www.notion.so/Backend-34a4b58e32c3808dbb2be218a09e73cd)
**Tracking:** [add a backend (Notion)](https://www.notion.so/add-a-backend-3274b58e32c380d29579c0861b8a199c?v=3174b58e32c38157ac2d000c36ca2e73&source=copy_link)
**Tag:** Per-phase — each phase doc declares its own (`#backendInfra`, `#backendAuth`, `#backendMigration`, `#backendSync<Entity>`, `#backendPush`).

> This file is the **roadmap**. Each phase below gets its own detailed implementation doc inside `documentation/Backend/` when we start that phase. Do not implement from this file directly.

---

## Context

SwiftData-only has burned us: the local store has been wiped multiple times during dogfooding (a month of workout data lost), and local notifications are unreliable across days/reinstalls — unacceptable for pill reminders. A future punishment/payment feature also needs server-side logic. The PRD locks the stack:

- **Postgres via Supabase** (international first; Alibaba Cloud RDS Supabase as the China path later — same API, different endpoint).
- **APNs directly** for push (FCM blocked in China).
- **Sign in with Apple + Supabase Auth.**
- **Local SwiftData remains source of truth**; Supabase is a sync/backup target. Last-write-wins.

The Notion PRD estimates 2–4 weeks of focused effort. The hardest pieces are offline sync, one-time migration of existing local stores, and auth integration — so we slice **risk-first**.

---

## Architecture Summary

```
┌─────────────────────────────┐         ┌──────────────────────────┐
│ iOS app (SwiftData = SoT)   │ ──push──▶│ Supabase Postgres        │
│  - writes locally first     │ ◀─pull── │  - row-level security    │
│  - SyncEngine (background)  │         │  - per-user rows          │
└──────────────┬──────────────┘         └────────────┬─────────────┘
               │                                      │
               │ local UNUserNotificationCenter       │ Edge Function
               ▼                                      ▼
        local notifications              APNs push (server backup)
```

- **Offline-first:** every write hits SwiftData synchronously; a `SyncEngine` enqueues outbound mutations and flushes to Supabase opportunistically.
- **Conflict resolution:** last-write-wins on a per-row `updatedAt` (server-stamped on accept).
- **Identity:** `userId` on every synced row. RLS on Supabase enforces isolation.
- **Migration:** existing dogfooding data uploads in full at first sign-in (one-shot, idempotent).

---

## Phase Slicing — Risk-First

Hardest unknowns first so we de-risk before we've built scaffolding around them. Each phase ships a usable, testable artifact and corresponds to one detailed implementation doc.


| #   | Phase                                                                                                                                                                                                                           | Risk addressed                                      | Detailed doc                                          | Tag                    |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- | ----------------------------------------------------- | ---------------------- |
| 0   | ~~Spike: Sync + Conflict + Migration prototype~~ **SKIPPED** — pattern is well-trodden (WatermelonDB / PowerSync / Supabase guides), risk is low; learning happens inside Phase 4 against production code instead of throwaway. | —                                                   | —                                                     |                        |
| 1a  | Smoke spike: Supabase project + 1 throwaway table + iOS SDK round-trip                                                                                                                                                          | SDK wiring, config plumbing, network reachability   | [`01a-Spike.md`](./01a-Spike.md)                      | `#backendSpike1a`      |
| 1b  | Real schema + RLS (mirrors SwiftData models)                                                                                                                                                                                    | Data model translation, perms                       | [`01b-Schema.md`](./01b-Schema.md)                    | `#backendSchema1b`     |
| 2   | Sign in with Apple + Supabase Auth                                                                                                                                                                                              | Identity, token lifecycle, SwiftData ↔ user binding | `02-Auth.md`                                          | `#backendAuth`         |
| 3   | One-time migration of existing local data                                                                                                                                                                                       | Idempotency, partial failure, dogfood data safety   | `03-Migration.md`                                     | `#backendMigration`    |
| 4   | SyncEngine: per-entity bidirectional sync                                                                                                                                                                                       | Crash safety, retry, ordering                       | `04-SyncEngine.md` (+ per-entity sub-docs `04a..04e`) | `#backendSync<Entity>` |
| 5   | Server push via Edge Function + APNs                                                                                                                                                                                            | Token registration, dedup w/ local                  | `05-Push.md`                                          | `#backendPush`         |
| 6   | China endpoint switch (deferred)                                                                                                                                                                                                | Region routing                                      | `06-China.md`                                         | `#backendChina`        |


### Why this order

- **Phase 0 skipped** — see table note above.
- **Auth before migration** because migration must attach data to a real `userId`, and we don't want to migrate twice.
- **Per-entity sync after auth+migration** so each entity ships incrementally and dogfoodable.
- **Push last** because it depends on user records existing server-side.
- **China deferred** — out of scope until international is solid.

### Dependencies

```
Phase 0 — SKIPPED

Phase 1 (infra) ──▶ Phase 2 (auth) ──▶ Phase 4 (sync engine + entities) ──▶ Phase 3 (migration)
                                                                       │
                                                                       ▼
                                                                Phase 5 (push)
                                                                       │
                                                                       ▼
                                                               Phase 6 (China, deferred)
```

Within Phase 4, entity sub-phases (`Commitment → Slot → CheckIn → PositivityToken → SlotSnooze → Tag → GracePeriod → Cycle`) can be parallelized once the engine core lands; order picked by dependency in the SwiftData graph.

---

## Sync & Conflict Model

This is a **single-user app** (one Apple ID = one human). True concurrent edits to the same row are rare, so we use the standard offline-first pattern shipped by WatermelonDB, PowerSync, and Supabase's own offline guides. No HLC, no per-field merge, no user-facing conflict UI.

**Per synced table, two extra columns:**

- `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()` — server-stamped on every write. Authoritative.
- `deleted_at TIMESTAMPTZ NULL` — soft-delete tombstone. UI filters these out; sync uses them so other devices learn about deletions instead of resurrecting rows on next push.

**App-side state:**

- `lastPulledAt` — high-watermark of the last successful pull. Persisted.
- **Outbox queue** — SwiftData table of pending local writes; processed in insertion order so foreign-key parents upload before children.

**Sync loop** (runs on app foreground + a timer when online):

1. **Push** outbox entries in order; drop each on success.
2. **Pull** rows where `updated_at > lastPulledAt`; insert / update / soft-delete locally.
3. Set `lastPulledAt` from the server's clock (returned by the pull endpoint), not the client's.

**Conflict resolution:** whichever write reaches the server last wins. Earlier edit is silently overwritten.

**Two table buckets:**


| Bucket             | Tables                                                    | Notes                                                                                          |
| ------------------ | --------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Mutable settings   | `Commitment`, `Tag`, `Cycle`, `Slot`                      | LWW + tombstones                                                                               |
| Append-only events | `CheckIn`, `PositivityToken`, `SlotSnooze`, `GracePeriod` | Insert-only with client-generated UUIDs; no conflict possible. Tombstones for the rare delete. |


### Known sharp edges (not blockers, but handle deliberately)

- **Use the server's clock for `lastPulledAt`** (return it from the pull endpoint) — client clocks lie.
- **Outbox must preserve insertion order** so FK parents upload before children; halt on error and retry.
- **Schema changes touch three places** (SwiftData model, Postgres column, sync mapper). Add a checklist; round-trip tests catch drift.
- **RLS policies need integration tests** that assert User A cannot see User B's rows. Don't trust eyeballing.
- **Client-generated UUIDs for all IDs** — never auto-increment. "Delete then recreate with same title" must be a new row.
- **Tombstone purge window:** 60–90 days. Devices offline longer must do a full resync.
- **Centralize the `deleted_at IS NULL` filter** in one SwiftData fetch helper; don't sprinkle it.

Phase 0's spike validates this end-to-end on `Commitment` + `CheckIn` before Phase 4 builds the production engine.

---

## Cross-cutting Decisions (locked)


| Decision                      | Choice                                                      | Why                                                                               |
| ----------------------------- | ----------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Source of truth               | Local SwiftData                                             | Offline-first; from PRD                                                           |
| Conflict resolution           | Row-level LWW with server-stamped `updated_at` + tombstones | Standard offline-first pattern; single-user app makes fancier schemes unnecessary |
| Auth                          | Sign in with Apple → Supabase Auth                          | PRD; required for App Store + China-friendly                                      |
| Migration policy              | **Full upload of existing local data** at first sign-in     | Preserve dogfooding history; cross-device continuity                              |
| Push transport                | APNs direct via Edge Function                               | FCM blocked in China                                                              |
| Dedup of local vs server push | **Deferred** to after Phase 5 lands                         | PRD: duplicates acceptable interim                                                |
| Region routing                | Single endpoint now; per-region endpoint later              | China path is Phase 6                                                             |


---

## Open Questions (to resolve in their respective phase docs, not now)

- How do we represent SwiftData relationships in Postgres (FK columns vs join tables) — Phase 1.
- Sync queue persistence: dedicated SwiftData entity vs file-backed log — Phase 0/4.
- What runs the SyncEngine: BGTask, scene-active timer, both — Phase 4.
- Migration progress UI / failure recovery — Phase 3.
- APNs token rotation, environment (sandbox vs prod) — Phase 5.

---

## Verification Strategy (applies to every phase)

Each phase doc must include its own verification, but all phases share these gates:

1. **Unit tests** for new logic, run via `./test-with-cleanup.sh` on iPhone 17 (UDID `4492FF84-2E83-4350-8008-B87DE7AE2588`).
2. **Manual dogfood** on the same simulator: install, sign in, perform a representative flow, kill+relaunch, verify state.
3. **Multi-device check** (from Phase 4 onwards): same Apple ID on simulator + a second device → mutate on one, observe on the other within N seconds.
4. **Data-loss drill** before declaring a phase done: wipe local store, reinstall, verify cloud restore matches expectation for that phase.

---

## How to Use This Roadmap

1. When starting a phase, create `documentation/Backend/<NN>-<Phase>.md` from `documentation/TEMPLATE.md`.
2. Header of that doc must link back here and to the tracking Notion page above.
3. Use the per-phase tag in commit messages plus `tracking: <link>`.
4. Update the table above with a link to the new doc once it exists.
5. If a phase reveals that a later phase's assumption is wrong, edit this file before continuing — the roadmap is allowed to change.

