# Release 1.0.0 (59)

## What's new (Play Store release notes)

- Fixed: Privacy Policy and Terms of Service links in Profile and Settings were unresponsive — they now open correctly.
- Fixed: Leaderboard accuracy percentages were showing incorrectly for some users.

## Technical details

- **Privacy Policy / Terms of Service links**: `ProfileScreen` and `SettingsScreen` had
  `onTap: () {}` stubs on both rows, so tapping them did nothing. Wired both up with
  `url_launcher` to open `https://nipino-manabu.com/privacy` and `/terms` externally,
  and added the Android 11+ `<queries>` package-visibility block required for
  `url_launcher` to reliably open `https://` links.
- **Leaderboard accuracy (`refresh_leaderboard()`, `backend/migrations/001_schema.sql`)**:
  - The all-time bucket's accuracy was incorrectly filtered to the last 7 days (a copy-paste
    of the weekly bucket's filter), so any user without quiz activity in the last week
    showed 0% accuracy in the All-time tab despite having real history. Fixed to average
    over the user's full `quiz_results` history.
  - Per-level (N5–N1) leaderboard snapshots were never generated at all, so every level tab
    in the app returned empty for every user. Added generation of per-level, all-time rows.
  - This fix has already been applied directly to the production database; it does not
    depend on this app release, but ships here to keep the migration file in sync for
    any future environment rebuild/restore.
- **Version bump**: `1.0.0+58` → `1.0.0+59`.

## Commits

- `263cdd9` — Wire up dead Privacy Policy / Terms of Service links, fix leaderboard accuracy bugs
- `9c43b14` — Bump version to 1.0.0+59 for release
