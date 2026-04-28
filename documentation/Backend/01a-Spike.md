# Phase 1a — Supabase Smoke Spike

**PRD:** [Backend (Notion)](https://www.notion.so/Backend-34a4b58e32c3808dbb2be218a09e73cd)
**Tracking:** TBD (3Sauce will paste a Notion sub-page URL before implementation begins)
**Tag:** `#backendSpike1a`

> Roadmap: [README.md](./README.md). Schema doc to follow this: [01b-Schema.md](./01b-Schema.md).

---

## Context

Before we design the full schema, we want to prove end-to-end that:

1. We can create a Supabase project.
2. The Supabase Swift SDK builds and links into the Wilgo Xcode project without breaking anything.
3. The iOS app can **insert + read** a row in a real Supabase table.
4. Our config plumbing (URL + anon key from xcconfig → Info.plist → SDK) actually works on the simulator.

Everything in Phase 1a is a **spike**. The temporary table and debug button get removed in Phase 1b before any real schema work starts. The only artifacts that survive are: the Supabase project itself, the SDK dependency, and the `SupabaseClient` singleton.

Decisions locked in earlier:

- **Region:** US-East (N. Virginia).
- **Environments:** Two projects, `wilgo-dev` and `wilgo-prod`. Phase 1a uses `wilgo-dev` only.
- **No RLS in this phase.** The spike table is world-readable/writable so we don't have to set up auth first. RLS is Phase 1b.
- **No sync columns** (`updated_at`, `deleted_at`, triggers). Those move to Phase 4 when SyncEngine actually needs them.

---

## Architecture Summary

```
┌─────────────────────────┐              ┌──────────────────────────┐
│ iOS app (debug button)  │ ── insert ──▶│ Supabase: wilgo-dev      │
│ Shared/Backend/         │              │   public.commitments_    │
│   SupabaseClient.swift  │ ◀── select ──│   spike (RLS DISABLED)   │
└─────────────────────────┘              └──────────────────────────┘
```

A single table, a single SDK call in each direction, no auth, no FK, no JSONB. If this round-trip works, every later phase has a paved on-ramp.

---

## Design Decisions

### One throwaway table, RLS off

**Decision:** Create `commitments_spike` with only `id UUID PRIMARY KEY`, `title TEXT NOT NULL`, `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`. RLS disabled.

**Why not the real `commitments` schema?** The real schema has 8+ columns including JSONB cycle/target/grace_periods, FK to users, RLS policies. If the round-trip fails we won't know whether the SDK is broken, the schema is wrong, or RLS is misconfigured. The spike isolates "can the iOS app talk to Supabase" from every other variable.

**Why not skip the table entirely and just call `auth.getSession()`?** Because writing a row is the actual thing we need to prove. A successful auth call doesn't mean inserts work — RLS, schema mismatch, encoding issues all live downstream of auth.

**Risk:** A leftover spike table in the dev project. **Mitigation:** Phase 1b's first commit drops it.

### Anon key via xcconfig, never committed

**Decision:** `Wilgo/Config/Supabase.xcconfig.template` is committed (with placeholder values); `Wilgo/Config/Supabase.local.xcconfig` is gitignored and holds the real values. Build settings reference the local file.

**Why?** Hardcoding the key in Swift means it lands in git history. Even though the anon key is "safe to publish" (RLS is what protects data), it leaks the project URL and discourages best practices.

### Debug button vs unit test

**Decision:** Both. A unit test for `./test-with-cleanup.sh` reproducibility + a temporary debug button in Settings for manual eyeball verification on the simulator.

**Why both?** The unit test catches regressions automatically. The debug button lets you watch the row appear in the Supabase dashboard — that's the moment of truth and worth seeing once with your own eyes.

Both get removed in Phase 1b's cleanup.

---

## Manual steps for 3Sauce

These need to happen before Phase 1a is fully testable. Most can be done **before** Commit 1; step 3 has to wait until after Commit 1 lands the template. ~15 minutes total.

**Do these now (before Commit 1):**

1. Create a Supabase organization (free) at [https://supabase.com](https://supabase.com).
2. Create **two** projects: `wilgo-dev` and `wilgo-prod`. Region: **US-East (N. Virginia)** for both. under Settings → General → "Project ID". Save both refs somewhere; you'll need the dev ref in step 7.
3. *(Defer until after Commit 1 lands the template file.)* From `wilgo-dev` Settings → API, copy Project URL + `anon` (publishable) key into `Wilgo/Config/Supabase.local.xcconfig`.
4. From the same page, copy the `service_role` key into 1Password / Apple Keychain. **Never** put it in the iOS app, in this repo, or in chat. Phase 1a does not use it.
5. `brew install supabase/tap/supabase`.
6. `supabase login` (opens a browser).
7. From the repo root (the directory containing `Wilgo/`, `WilgoTests/`, `Shared/`): `supabase init`, then `supabase link --project-ref <wilgo-dev-ref>` (substitute the dev ref from step 2 — e.g. `supabase link --project-ref abcdwxyzqrstuvwxyz12`).

Confirm steps 1, 2, 4, 5, 6, 7 are done; I'll start Commit 1. Step 3 happens right after Commit 1 lands.

---

## Major Model Changes


| Entity                                                        | Change                                                          |
| ------------------------------------------------------------- | --------------------------------------------------------------- |
| **New:** `supabase/` (CLI scaffold)                           | New top-level dir with `config.toml` and `migrations/`          |
| **New:** `supabase/migrations/0001_spike_table.sql`           | Creates `commitments_spike`, RLS disabled                       |
| **New:** `Wilgo/Config/Supabase.xcconfig.template`            | Committed, placeholder values                                   |
| **New:** `Wilgo/Config/Supabase.local.xcconfig`               | Gitignored, real values                                         |
| **New:** `Shared/Backend/SupabaseClient.swift`                | `enum Backend { static let client: SupabaseClient }`            |
| `Wilgo.xcodeproj`                                             | Add `supabase-swift` SPM dependency; wire xcconfig → Info.plist |
| `.gitignore`                                                  | Add `Wilgo/Config/Supabase.local.xcconfig`                      |
| **New (temp):** Debug button in `SettingsView.swift`          | "Spike: Insert + Read" — removed in Phase 1b                    |
| **New (temp):** `WilgoTests/Backend/SupabaseSpikeTests.swift` | Round-trip test — removed in Phase 1b                           |


---

## Commit Plan

**Tag for every commit in this phase:** `#backendSpike1a`

### Commit 1 — Supabase project skeleton + spike table

**Create:**

- `supabase/config.toml` (output of `supabase init`).
- `supabase/migrations/0001_spike_table.sql`:
  ```sql
  CREATE TABLE public.commitments_spike (
      id UUID PRIMARY KEY,
      title TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );
  -- RLS intentionally DISABLED for the spike.
  ```
- `Wilgo/Config/Supabase.xcconfig.template`:
  ```
  SUPABASE_URL = https://YOUR_PROJECT_REF.supabase.co
  SUPABASE_ANON_KEY = your_anon_key_here
  ```

**Modify:** `.gitignore` — add `Wilgo/Config/Supabase.local.xcconfig`.

**Manual (3Sauce):** create `Supabase.local.xcconfig` from the template, paste real values. Run `supabase db push` — verify the table appears in the dashboard.

**Acceptance:** `supabase db push` exits 0; table visible in dashboard with RLS off (no lock icon).

### Commit 2 — Add Supabase Swift SDK + `SupabaseClient` singleton

**Modify:** `Wilgo.xcodeproj` — add `supabase-swift` SPM package (latest stable). Add `Supabase` product to the `Wilgo` and `WilgoTests` targets.

**Modify:** Xcode build settings — link `Supabase.local.xcconfig` for both Debug and Release configs of `Wilgo`. Add `SUPABASE_URL` and `SUPABASE_ANON_KEY` to `Info.plist` referencing the build settings: `$(SUPABASE_URL)`, `$(SUPABASE_ANON_KEY)`.

**Create:** `Shared/Backend/SupabaseClient.swift`:

```swift
import Foundation
import Supabase

enum Backend {
    static let client: SupabaseClient = {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let url = URL(string: urlString),
            let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            !key.isEmpty
        else {
            fatalError("Supabase config missing — check Supabase.local.xcconfig")
        }
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }()
}
```

**Acceptance:** `xcodebuild build` on iPhone 17 succeeds. App launches. No runtime errors. (We're not calling the client yet.)

Depends on Commit 1 only for the project URL/key existing in the dev project; if those are pasted in, this commit can run in parallel with Commit 3.

### Commit 3 — Round-trip test + temporary debug button

**Create:** `WilgoTests/Backend/SupabaseSpikeTests.swift`:

- `testInsertAndReadCommitmentSpike()`:
  1. Generate a fresh UUID and title.
  2. `try await Backend.client.from("commitments_spike").insert(...)`.
  3. `try await Backend.client.from("commitments_spike").select().eq("id", uuid).single().execute()` — decode into a local `SpikeRow: Decodable` struct.
  4. Assert title matches.
  5. `try await Backend.client.from("commitments_spike").delete().eq("id", uuid).execute()` — clean up.
- Skip the test if `SUPABASE_URL` is empty (so CI without secrets doesn't fail).

**Modify:** `Wilgo/Features/Settings/SettingsView.swift` — add a `#if DEBUG` section with a button "Spike: Insert + Read" that runs the same flow and shows a `Text` with the result ("OK: " or "FAIL: "). Marked clearly as TEMPORARY with a `// TODO: remove in Phase 1b cleanup` comment.

**Acceptance:**

1. `./test-with-cleanup.sh` passes (the spike test passes against the live dev project).
2. **Manual on iPhone 17 (UDID `4492FF84-2E83-4350-8008-B87DE7AE2588`):** open Settings, tap the spike button, see "OK". Refresh Supabase dashboard's table editor for `commitments_spike` — see the row appear, then disappear after the test cleanup.
3. No regressions in any pre-existing test.

Depends on Commits 1 and 2.

### Commit 4 — Update roadmap pointer

**Modify:** [documentation/Backend/README.md](./README.md) — Phase 1 row points to both `01a-Spike.md` (this) and `01b-Schema.md` (next).

---

## Critical Files


| File                                                       | Role                                   |
| ---------------------------------------------------------- | -------------------------------------- |
| `supabase/migrations/0001_spike_table.sql`                 | The throwaway table                    |
| `Wilgo/Config/Supabase.local.xcconfig` (gitignored)        | Real URL + key                         |
| `Shared/Backend/SupabaseClient.swift`                      | The singleton everything else will use |
| `WilgoTests/Backend/SupabaseSpikeTests.swift` (temp)       | Proves the round-trip                  |
| `Wilgo/Features/Settings/SettingsView.swift` (temp button) | Manual round-trip verification         |


### Dependency Graph

```
Commit 1 (project + table)
   │
   ├── Commit 2 (SDK + singleton)  [parallel after manual setup]
   │       │
   │       └── Commit 3 (test + debug button)
   │
   └── Commit 4 (README pointer)  [parallel after 1]
```

---

## Verification

End-to-end Phase 1a acceptance:

1. `**./test-with-cleanup.sh**` passes on iPhone 17 (UDID `4492FF84-2E83-4350-8008-B87DE7AE2588`) — `SupabaseSpikeTests.testInsertAndReadCommitmentSpike` passes against the live dev project. No regressions.
2. **Manual round-trip:** launch app on iPhone 17, open Settings, tap "Spike: Insert + Read" → result shows "OK: ". In Supabase dashboard, watch the row appear in `commitments_spike` and get cleaned up.
3. **Build cleanly with no config:** if `Supabase.local.xcconfig` is missing, the app fatal-errors at first access of `Backend.client` with a clear message — not a silent misconfiguration.
4. **Anon key not in git:** `git log -p -- 'Wilgo/Config/*'` shows only the template, never the local file.

When all four pass, Phase 1a is done and we can start [01b-Schema.md](./01b-Schema.md).