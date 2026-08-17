# Changelog

## [0.2.0] - 2026-08-17

- New target-mode settings: the existing focused-text converter remains on
  `⌥F`, while a fully independent clipboard cleaner defaults to `⌥A`.
- Clipboard cleaning strips rich formatting and supports all legacy Plain Clip
  transforms: per-line/whole-text trimming, invisible characters, line breaks,
  blank lines, spaces, tabs, safe ASCII transliteration, straight quotes, and
  Unicode NFC. Unsupported scripts such as Chinese remain unchanged instead
  of becoming question marks.
- Optional clean-and-paste, multi-item clipboard preservation, change-count
  race protection, and a no-text alert without destructive clipboard writes.
- Plain Clip-compatible one-shot CLI flags:
  `-w -l -m -i -r -b -s -p -a -q -n -v` (or `--plain-clip`).
- Fix: stop the Accessibility permission sheet from reappearing on every
  hotkey press when two halfFull processes were alive at once (e.g.
  `/Applications/halfFull.app` + a local `build/` copy). Enforce a single
  instance at launch and relaunch without `open -n`.
- Defense in depth: only fire the system Accessibility prompt once per
  process lifetime, even if the hotkey keeps hitting the untrusted path.

## [0.1.5] - 2026-07-09

- Under the hood: `@Pref` property wrapper folds the PreferencesStore
  send-then-set ritual (interface unchanged).
- No intentional user-facing behavior change.

## [0.1.4] - 2026-07-09

- Under the hood: collapse focused-field edit into a deep `EditableField`
  module (AX write + clipboard fallback hidden behind one seam).
- Under the hood: pure `ConversionPolicy` routes trust + field outcome to a
  user-feedback plan; `ConversionController` is now an imperative shell only.
- Under the hood: `HotKey` value type and shared `TrustState` derivation —
  fewer paired parameters, one place for the stale-grant rule.
- No intentional user-facing behavior change.

## [0.1.3] - 2026-07-02

- New **Show in menu bar** setting (default on). Uncheck it to hide the
  menu-bar icon — the global hotkey keeps working; open the app again from
  Launchpad/Finder/Spotlight to bring back the settings window.
- Login-item launches are now detected from the launching Apple Event
  (`keyAELaunchedAsLogInItem`) instead of a boot-time heuristic, so manually
  opening the app right after login reliably shows the window.
- Stopped opting into automatic termination (`NSSupportsAutomaticTermination`):
  once the icon is hidden and the window closed the app had zero visible
  surfaces, and macOS was allowed to silently kill it — taking the global
  hotkey down with it.

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
