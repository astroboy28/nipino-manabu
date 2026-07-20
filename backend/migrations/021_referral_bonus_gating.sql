-- backend/migrations/021_referral_bonus_gating.sql
-- ─── Referral anti-abuse: gate the referrer's payout on real activity ────────
-- Previously both sides of a referral got paid the instant the code was
-- claimed, with no limit — two colluding accounts could reciprocally claim
-- each other's codes for unlimited free coins. Two changes fix this:
--   1. The referrer's bonus now pays out only once the referee completes
--      their first quiz (see handleSubmit in quiz.php), not on signup alone.
--   2. A lifetime cap (config: referral_lifetime_cap) limits how many times
--      a single account can be paid for referring someone.
-- This column lives on the referee's row (which already carries
-- referred_by_id) and marks when that referral was *resolved* — NULL means
-- still pending a qualifying quiz, non-NULL means it's been resolved (paid
-- to the referrer, or silently skipped for hitting the cap; either way,
-- nothing should re-check it again).

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS referral_bonus_paid_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_users_referral_pending
  ON users(referred_by_id)
  WHERE referred_by_id IS NOT NULL AND referral_bonus_paid_at IS NULL;
