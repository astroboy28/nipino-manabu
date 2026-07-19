-- backend/migrations/019_weekly_leaderboard_reset.sql
-- ─── True calendar-week leaderboard reset ─────────────────────────────────────
-- 'weekly' has always been a rolling 7-day window, recalculated daily -- there
-- was no real competition boundary, just a window that slides forward every
-- day. This switches it to a real calendar week (Monday 00:00 Asia/Tokyo to
-- the next Monday), and adds a permanent record of each week's final
-- standings so a "reset" actually means something (weekly_leaderboard.php
-- reads this to announce last week's results).
--
-- The week boundary MUST be computed as
-- (date_trunc('week', NOW() AT TIME ZONE 'Asia/Tokyo') AT TIME ZONE 'Asia/Tokyo')
-- and NOT bare date_trunc('week', NOW()) -- Database.php's every PHP
-- connection runs `SET TIME ZONE 'UTC'`, so a plain date_trunc('week', NOW())
-- computes the Monday boundary in UTC (9 hours off from JST) despite the
-- database's own default timezone being Asia/Tokyo. Confirmed by testing
-- through the app's real PDO connection on staging, not just via a manual
-- psql session (which defaults to Asia/Tokyo and would have hidden this).
\c nipino_manabu;

CREATE TABLE IF NOT EXISTS leaderboard_history (
  id           SERIAL PRIMARY KEY,
  period_start DATE    NOT NULL,
  period_end   DATE    NOT NULL,
  user_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  rank_pos     INTEGER NOT NULL,
  total_score  INTEGER NOT NULL,
  accuracy     NUMERIC(5,2),
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(period_start, user_id)
);
CREATE INDEX IF NOT EXISTS idx_lh_period ON leaderboard_history(period_start, rank_pos);

CREATE OR REPLACE FUNCTION refresh_leaderboard() RETURNS VOID AS $$
BEGIN
  -- All-time
  DELETE FROM leaderboard_snapshots WHERE period = 'alltime' AND level IS NULL;
  INSERT INTO leaderboard_snapshots (user_id, period, level, total_score, accuracy, rank_pos)
  SELECT u.id, 'alltime', NULL, u.total_score,
    COALESCE(AVG(qr.score_percent), 0),
    ROW_NUMBER() OVER (ORDER BY u.total_score DESC)
  FROM users u
  LEFT JOIN quiz_results qr ON qr.user_id = u.id
  WHERE u.is_active = TRUE
  GROUP BY u.id
  ON CONFLICT (user_id, period, level) DO UPDATE
    SET total_score=EXCLUDED.total_score,
        accuracy=EXCLUDED.accuracy,
        rank_pos=EXCLUDED.rank_pos,
        snapshot_at=NOW();

  -- Weekly — calendar week (Mon 00:00 -> next Mon 00:00), not a rolling window.
  DELETE FROM leaderboard_snapshots WHERE period = 'weekly' AND level IS NULL;
  INSERT INTO leaderboard_snapshots (user_id, period, level, total_score, accuracy, rank_pos)
  SELECT u.id, 'weekly', NULL,
    COALESCE(SUM(qr.correct_count * 10), 0),
    COALESCE(AVG(qr.score_percent), 0),
    ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(qr.correct_count * 10), 0) DESC)
  FROM users u
  LEFT JOIN quiz_results qr ON qr.user_id = u.id
    AND qr.taken_at >= (date_trunc('week', NOW() AT TIME ZONE 'Asia/Tokyo') AT TIME ZONE 'Asia/Tokyo')
  WHERE u.is_active = TRUE
  GROUP BY u.id
  ON CONFLICT (user_id, period, level) DO UPDATE
    SET total_score=EXCLUDED.total_score,
        accuracy=EXCLUDED.accuracy,
        rank_pos=EXCLUDED.rank_pos,
        snapshot_at=NOW();

  -- Per-level, all-time
  DELETE FROM leaderboard_snapshots WHERE period = 'alltime' AND level IS NOT NULL;
  INSERT INTO leaderboard_snapshots (user_id, period, level, total_score, accuracy, rank_pos)
  SELECT u.id, 'alltime', qr.level,
    SUM(qr.correct_count * 10),
    COALESCE(AVG(qr.score_percent), 0),
    ROW_NUMBER() OVER (PARTITION BY qr.level ORDER BY SUM(qr.correct_count * 10) DESC)
  FROM users u
  JOIN quiz_results qr ON qr.user_id = u.id
  WHERE u.is_active = TRUE
  GROUP BY u.id, qr.level
  ON CONFLICT (user_id, period, level) DO UPDATE
    SET total_score=EXCLUDED.total_score,
        accuracy=EXCLUDED.accuracy,
        rank_pos=EXCLUDED.rank_pos,
        snapshot_at=NOW();
END;
$$ LANGUAGE plpgsql;
