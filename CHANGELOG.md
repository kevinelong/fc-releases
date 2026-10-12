# Release history

## 1.0.3 — versionCode 4 — 12 October 2026

The current release. Download from the
[releases page](https://github.com/kevinelong/fc-releases/releases/latest).

- 22 example games, up from 17 — including the generative toys (matrix rain, falling sand,
  starfield, life, langton) and five multiplayer games
- Dialogue and NPCs: `when player talks to "guard"`, `show dialog`, `show choice`
- Dynamic colours: `draw rect … in shade` follows the variable, so fades, parallax and
  multi-tone effects work
- Accessibility settings: colourblind-safe palette, reduced motion, larger high-contrast text
- The map editor opens from inside the app (it was missing from the bundle before)
- The guide, command reference, teacher pages, projects and privacy policy are bundled, so
  they work offline
- Plainer runtime messages — a mistake now says what happened and which line to look at — and
  ten verbs that used to do nothing (particles, `emit`, several dialogue forms) now work

*Installing over an older copy:* uninstall 1.0.2 first. This build is signed with a new key,
so Android cannot replace the old copy in place.

## 1.0.2 — versionCode 3 — 2 July 2026

The previous build, distributed directly at <https://codeonline.io/fc.apk>. Built from the
web app as it stood in July: 17 example games, no dialogue, no dynamic colours, no
accessibility settings, and the guide, teacher and privacy pages not yet bundled.
