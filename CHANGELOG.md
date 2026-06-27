# Changelog

## [0.1.2] - 2026-06-27

- Ship as a universal binary (arm64 + x86_64). Earlier 0.1.x releases were arm64-only, which silently broke installs on Intel Macs.

## [0.1.1] - 2026-06-27

- In-app permission recovery for the common "TCC grant invalidated after an ad-hoc-signed update" trap. When the main window detects the stale-grant state it now offers a single **Recover Permission** button that runs `tccutil reset` for our bundle id, relaunches a fresh process, and auto-fires the system permission prompt — no Terminal required.

## [0.1.0] - 2026-06-27

First public release.

- Global hotkey `⌥F` — convert the focused text field from half-width to
  full-width (or vice versa, via Smart mode).
- Focus guard: query the macOS Accessibility tree first and refuse to act
  if the focused element isn't a text-editing element. No destructive ⌘A
  in Finder or on the desktop.
- AX direct edit preferred (clipboard untouched, no synthetic keystrokes).
  Clipboard fallback only when the target app rejects AX writes.
- Single-page settings window: hotkey recorder, conversion direction,
  scope, behavior toggles, launch-at-login, about.
- Three conversion directions (Smart / half→full / full→half) and three
  scopes (everything / punctuation / letters & digits).
- Free for personal / educational / noncommercial use under
  [PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/).
