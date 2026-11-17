# Kyo

A macOS meeting reminder that lives in the notch. README.md covers what it does.

- Tests: `swift test`
- Build: `Scripts/build-app.sh` → `build/Kyo.app`
- See it work: `open build/Kyo.app --args --demo --snapshot <dir>` plays a
  made-up day through every phase and writes a PNG of the panel each second,
  plus a log of clicks and hovers. Use this to check the drawing when a
  screenshot is not possible.

## Conventions

- Logic that can be tested without a screen belongs in `KyoCore`, test first.
- Calendar content is untrusted: anyone can send an invite. Whatever is built
  from an event's title, location, notes or links has to be checked, and links
  are rebuilt from validated parts, never edited in place.
- The app makes no network requests. Keep it that way.
