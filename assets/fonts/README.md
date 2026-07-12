# Nipino-Manabu — Font Setup

## Required fonts

The app uses **Noto Sans JP** for all Japanese character rendering.
These font files MUST be placed in `flutter_app/assets/fonts/` before building.

## Download instructions

1. Go to: https://fonts.google.com/noto/specimen/Noto+Sans+JP
2. Click **"Download family"**
3. Extract the zip file
4. Copy these three files into `flutter_app/assets/fonts/`:

| File to copy                     | Rename to                        |
|----------------------------------|----------------------------------|
| `NotoSansJP-Regular.ttf`         | `NotoSansJP-Regular.ttf`         |
| `NotoSansJP-Medium.ttf`          | `NotoSansJP-Medium.ttf`          |
| `NotoSansJP-Bold.ttf`            | `NotoSansJP-Bold.ttf`            |

Alternatively, run this from the project root:

```bash
# macOS/Linux
cd flutter_app/assets/fonts
curl -L "https://fonts.gstatic.com/s/notosansjp/v52/-F6jfjtqLzI2JPCgQBnw7HFyzSD-AsregP8VFBEi75vY0rw-oME.woff2" -o tmp.woff2
# NOTE: Use the TTF variant for mobile apps, not WOFF2
# Download the full family zip from fonts.google.com instead
```

## Why this matters

Without these fonts:
- Japanese characters (kanji, hiragana, katakana) will render as boxes or fallback fonts
- The quiz questions will be unreadable
- Apple may reject the app during review for broken UI

## License

Noto Sans JP is licensed under the **SIL Open Font License 1.1** —
free for commercial use, no attribution required in the app UI
(though you may credit it in your App Store description).
