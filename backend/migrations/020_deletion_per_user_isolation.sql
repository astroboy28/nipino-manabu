-- backend/migrations/020_deletion_per_user_isolation.sql
-- ─── Isolate each user's deletion so one failure can't block the whole batch ──
-- execute_scheduled_deletions() ran its entire FOR loop as a single implicit
-- transaction with no per-iteration exception handling. One user hitting an
-- unexpected error (a future non-cascading FK, a trigger, anything) would
-- abort the whole function and roll back every deletion for that day's run
-- -- the exact failure mode already found once this session in
-- handleAdminFinalize() (challenge.php), just with GDPR erasure requests
-- instead of coin payouts. Wrapping each user's work in its own
-- BEGIN/EXCEPTION block (an implicit savepoint) means a bad row logs a
-- warning and gets skipped instead of blocking everyone else.
\c nipino_manabu;

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
    BEGIN
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
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'execute_scheduled_deletions: failed for user % (%): %',
        rec.id, rec.email, SQLERRM;
    END;
  END LOOP;

  RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;
