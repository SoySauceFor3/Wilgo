-- Phase 1a — Supabase smoke spike.
-- This table proves the iOS app can round-trip a row through Supabase.
-- Phase 1b's first commit DROPs this table.
-- RLS is intentionally disabled so the anon key can read/write without auth.

CREATE TABLE public.commitments_spike (
    id          UUID         PRIMARY KEY,
    title       TEXT         NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
