-- 015_challenge_events_finished_at.sql
-- handleAdminFinalize() (backend/api/challenge.php) has always written
-- finished_at=NOW() when closing out a challenge_events row, but the column
-- was never added to the table -- every finalize call has been throwing
-- "column finished_at does not exist" and rolling back, silently failing
-- ("Finalization failed.") since the challenge feature was first built.
ALTER TABLE challenge_events ADD COLUMN IF NOT EXISTS finished_at TIMESTAMPTZ;
