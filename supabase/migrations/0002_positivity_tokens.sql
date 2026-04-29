-- Phase 1b commit 1: positivity_tokens — first real synced table.
-- Mirrors Shared/Models/PositivityToken.swift.
--
-- RLS is intentionally NOT enabled here. We add it in one sweep after
-- Phase 2 wires Sign in with Apple, so RLS can be tested against real
-- auth.uid() instead of bypassed via the service-role key.
-- The user_id column is in place now so the future RLS migration is a
-- pure ALTER TABLE without backfill.

CREATE TABLE public.positivity_tokens (
    id              UUID         PRIMARY KEY,
    user_id         UUID         NOT NULL,
    reason          TEXT         NOT NULL,
    created_at      TIMESTAMPTZ  NOT NULL,
    status          TEXT         NOT NULL,
    day_of_status   TIMESTAMPTZ  NULL
);
