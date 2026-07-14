-- backend/migrations/013_admin_ban_columns.sql
-- ─── Admin moderation: ban/unban columns, separate from GDPR deletion ─────────
-- is_active already does double duty as "account is usable" (checked by
-- login/refresh) and gets set FALSE by account.php's request-deletion flow.
-- An admin ban needs the same functional gate (is_active=FALSE blocks
-- login/refresh — see auth.php handleLogin, handleRefresh) but must stay
-- distinguishable from "user requested their own deletion": a banned row has
-- deletion_scheduled_at IS NULL, so it never collides with the 30-day
-- deletion/cancel-token flow (migration 012) or its "already scheduled"
-- checks. banned_at is purely a descriptive audit marker; is_active remains
-- the one functional gate everything else already checks.
\c nipino_manabu;

ALTER TABLE users ADD COLUMN IF NOT EXISTS banned_at    TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS ban_reason   VARCHAR(500);
ALTER TABLE users ADD COLUMN IF NOT EXISTS banned_by_id INTEGER REFERENCES users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_users_banned ON users(banned_at) WHERE banned_at IS NOT NULL;
