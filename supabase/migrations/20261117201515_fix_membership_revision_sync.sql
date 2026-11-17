-- The existing membership update trigger increments revision, but this table
-- was created without the revision column. Keep it consistent with sync rows.
ALTER TABLE public.shared_memberships
  ADD COLUMN IF NOT EXISTS revision bigint NOT NULL DEFAULT 0;
