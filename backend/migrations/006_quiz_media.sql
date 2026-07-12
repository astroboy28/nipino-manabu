-- backend/migrations/006_quiz_media.sql
-- Run after 005_web_payments.sql
\c nipino_manabu;

ALTER TABLE quiz_questions
  ADD COLUMN IF NOT EXISTS image_url    VARCHAR(500),
  ADD COLUMN IF NOT EXISTS audio_url    VARCHAR(500),
  ADD COLUMN IF NOT EXISTS media_credit VARCHAR(200);

CREATE TABLE IF NOT EXISTS media_uploads (
  id            SERIAL PRIMARY KEY,
  uploader_id   INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  file_type     VARCHAR(10)  NOT NULL CHECK (file_type IN ('image','audio')),
  original_name VARCHAR(255) NOT NULL,
  storage_key   VARCHAR(500) NOT NULL UNIQUE,
  public_url    VARCHAR(500) NOT NULL,
  file_size_kb  INTEGER      NOT NULL,
  mime_type     VARCHAR(100) NOT NULL,
  question_id   INTEGER      REFERENCES quiz_questions(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ  DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mu_uploader ON media_uploads(uploader_id);
CREATE INDEX IF NOT EXISTS idx_mu_question ON media_uploads(question_id);
CREATE INDEX IF NOT EXISTS idx_mu_type     ON media_uploads(file_type, created_at DESC);

ALTER TABLE quiz_questions
  DROP CONSTRAINT IF EXISTS quiz_questions_question_type_check;

ALTER TABLE quiz_questions
  ADD CONSTRAINT quiz_questions_question_type_check
  CHECK (question_type IN (
    'reading','meaning','grammar_fill',
    'listening','image_reading','image_meaning'
  ));
