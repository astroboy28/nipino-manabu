-- backend/migrations/018_referral_code_default.sql
-- ─── Backfill: codify an undocumented production schema change ───────────────
-- users.referral_code has had a DEFAULT on production for some time (auth.php's
-- handleRegister() INSERT never sets it explicitly, so registration has always
-- relied on this), but no migration file ever recorded it -- rebuilding the
-- schema from migrations 001-017 alone produces a users table that rejects
-- every new registration with a NOT NULL violation. Discovered by replaying
-- all migrations against a fresh staging database.
\c nipino_manabu;

ALTER TABLE users ALTER COLUMN referral_code
  SET DEFAULT upper(substring(md5(random()::text) from 1 for 8));
