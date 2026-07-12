-- backend/migrations/007_is_admin.sql
-- ─── Admin role flag ─────────────────────────────────────────────────────────
-- challenge.php's requireAdmin() and media.php's guard() have queried
-- users.is_admin since they were written, but no migration ever created the
-- column — every admin-only endpoint has been throwing an uncaught
-- PDOException (500) instead of enforcing the check. This adds the column.
\c nipino_manabu;

ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN NOT NULL DEFAULT FALSE;

-- To promote an account to admin, run:
--   UPDATE users SET is_admin = TRUE WHERE email = 'you@example.com';
