-- backend/migrations/003_account_deletion_gdpr.sql
-- Run after 002_auth_and_monitoring.sql

\c nipino_manabu;

-- ── Column for soft-delete / scheduled deletion ───────────────────────────────
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS deletion_scheduled_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_users_deletion_scheduled
  ON users(deletion_scheduled_at)
  WHERE deletion_scheduled_at IS NOT NULL;

-- ── Allow quiz_results user_id to be NULL (anonymised on hard delete) ─────────
ALTER TABLE quiz_results
  ALTER COLUMN user_id DROP NOT NULL;

-- ── GDPR data export log ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS gdpr_export_log (
  id         SERIAL PRIMARY KEY,
  user_id    INTEGER     NOT NULL,   -- no FK — user may be deleted
  ip_address INET,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── Hard-delete accounts that passed 30-day grace period ──────────────────────
-- Called by cron/daily.php
CREATE OR REPLACE FUNCTION execute_scheduled_deletions() RETURNS INTEGER AS $$
DECLARE
  deleted_count INTEGER := 0;
  rec           RECORD;
BEGIN
  FOR rec IN
    SELECT id, email, username
    FROM users
    WHERE deletion_scheduled_at IS NOT NULL
      AND deletion_scheduled_at <= NOW()
  LOOP
    -- Anonymise quiz results
    UPDATE quiz_results SET user_id = NULL WHERE user_id = rec.id;

    -- Anonymise error logs
    UPDATE error_log
    SET user_id = NULL, ip_address = NULL
    WHERE user_id = rec.id;

    -- Hard delete cascade tables
    DELETE FROM user_badges          WHERE user_id = rec.id;
    DELETE FROM user_level_progress  WHERE user_id = rec.id;
    DELETE FROM refresh_tokens       WHERE user_id = rec.id;
    DELETE FROM password_reset_tokens WHERE user_id = rec.id;
    DELETE FROM leaderboard_snapshots WHERE user_id = rec.id;
    DELETE FROM notification_log     WHERE user_id = rec.id;
    DELETE FROM iap_purchases        WHERE user_id = rec.id;

    -- Delete user row
    DELETE FROM users WHERE id = rec.id;

    deleted_count := deleted_count + 1;
  END LOOP;

  RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- ── Fix: enforce minimum quiz question count ──────────────────────────────────
-- (prevents count=0 crash in Flutter)
-- Handled in PHP but also add a DB-level guard for belt-and-suspenders safety.
-- No schema change needed — the PHP layer now enforces count >= 1.

-- ── Composite index for leaderboard queries ───────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_lb_period_rank
  ON leaderboard_snapshots(period, level, rank_pos);

-- ── Index for quiz history pagination ────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_qr_user_taken
  ON quiz_results(user_id, taken_at DESC NULLS LAST)
  WHERE user_id IS NOT NULL;
