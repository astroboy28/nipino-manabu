-- backend/migrations/014_quiz_wrong_answer_penalty.sql
-- ─── Coin penalty for wrong quiz answers ──────────────────────────────────────
-- Regular practice quizzes now deduct coins per wrong answer (see quiz.php
-- handleSubmit) and block starting a new quiz once the balance hits 0 (see
-- handleGetQuestions). Add the new ledger type so those deductions can be
-- recorded the same way every other coin movement in this app already is.
\c nipino_manabu;

ALTER TABLE coin_transactions DROP CONSTRAINT IF EXISTS coin_transactions_type_check;
ALTER TABLE coin_transactions ADD CONSTRAINT coin_transactions_type_check
  CHECK (type IN (
    'quiz_reward','streak_bonus','iap_purchase',
    'duel_bet_debit','duel_win','duel_refund',
    'challenge_prize','referral_bonus','admin_grant',
    'quiz_wrong_penalty'
  ));
