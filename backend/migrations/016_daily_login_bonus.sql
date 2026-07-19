-- 016_daily_login_bonus.sql
-- Tracks the last calendar date a user claimed their daily login bonus,
-- so handleDailyBonus() (backend/api/user.php) can award it at most once
-- per day via an atomic UPDATE ... WHERE last_login_bonus_date < CURRENT_DATE.
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_bonus_date DATE;
