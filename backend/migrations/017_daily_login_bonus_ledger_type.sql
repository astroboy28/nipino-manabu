-- backend/migrations/017_daily_login_bonus_ledger_type.sql
-- ─── Add daily_login_bonus to the coin_transactions type allowlist ───────────
-- handleDailyBonus() (see api/user.php) writes 'daily_login_bonus' rows, but
-- the CHECK constraint from migration 014 didn't know about the new type —
-- every claim was throwing a check-violation and rolling back the award.
\c nipino_manabu;

ALTER TABLE coin_transactions DROP CONSTRAINT IF EXISTS coin_transactions_type_check;
ALTER TABLE coin_transactions ADD CONSTRAINT coin_transactions_type_check
  CHECK (type IN (
    'quiz_reward','streak_bonus','iap_purchase',
    'duel_bet_debit','duel_win','duel_refund',
    'challenge_prize','referral_bonus','admin_grant',
    'quiz_wrong_penalty','daily_login_bonus'
  ));
