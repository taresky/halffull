# Target modes and Plain Clip integration

Date: 2026-08-17

## Goal

Make halfFull target-mode driven and add the complete Plain Clip workflow as a
second target without changing the existing focused-field conversion behavior.

## Target modes

halfFull has two simultaneously active targets:

1. **Focused text** — the existing width conversion. Default hotkey: `⌥F`.
2. **Clipboard** — replace text on the general pasteboard with plain text.
   Default hotkey: `⌥A`.

Each target owns an independently configurable hotkey. The settings window
selects a target and shows only the settings relevant to that target. Shared app
preferences (sound, notifications, menu-bar visibility, login launch) remain
shared.

## Plain Clip behavior

On a clipboard request:

1. Read every pasteboard item that has a `.string` representation.
2. If no item has text, leave the pasteboard untouched and play the system alert
   sound.
3. Apply the configured text-cleaning pipeline independently to each text item.
4. Before writing, verify `changeCount` has not changed. Never overwrite newer
   clipboard content.
5. Clear the pasteboard and write one `.string`-only item per input text item.
   Rich text, HTML, file URL, attachment, image, and private representations are
   intentionally removed.
6. Optionally synthesize `⌘V` after a successful write. This is off by default.

The app does not monitor or retain clipboard history.

## Cleaning options

All cleaning options default to off, matching Plain Clip's documented defaults:

- Remove trailing spaces and tabs from every line (`-w`).
- Remove leading spaces and tabs from every line (`-l`).
- Trim whitespace and line breaks around the whole string (`-m`).
- Remove invisible control and format characters while preserving tabs and line
  breaks (`-i`).
- Remove hard line wraps (`-r`): join adjacent nonblank lines with a space while
  preserving paragraph boundaries, matching Plain Clip's actual legacy behavior.
- Remove blank lines (`-b`).
- Replace consecutive ASCII spaces with one space (`-s`).
- Replace tabs with spaces (`-p`).
- Convert supported characters to ASCII while preserving unsupported scripts (`-a`).
- Replace smart single/double quotes with straight quotes (`-q`).
- Normalize Unicode to NFC (`-n`).

The pipeline has one deterministic order verified against the legacy binary:
trailing line trim, leading line trim, invisible removal, hard-wrap removal,
NFC, tabs, consecutive spaces, blank-line removal, smart quotes, ASCII, whole
string trim.

## Command-line compatibility

Calling the halfFull executable with `--plain-clip` or any legacy Plain Clip flag
runs the clipboard target once. The supported flags are:

`-w -l -m -i -r -b -s -p -a -q -n -v`

Without cleaning flags, the command only removes non-string pasteboard
representations. `-v` additionally pastes. Command-line options override saved
Plain Clip settings for that invocation. If the normal app is already running,
the short-lived command process performs the action itself without activating or
otherwise disturbing the resident app. This avoids exposing trusted keyboard
injection through unauthenticated local notifications.

## Confirmed test seams

- `TargetMode`: target identity and default hotkey mapping.
- `PlainTextCleaner`: input string plus options to output string.
- `ClipboardPlainifier`: pasteboard plus cleaner options to observable result and
  resulting pasteboard items.

Tests use named pasteboards and never modify the user's general pasteboard.

## Out of scope

- Automatic clipboard monitoring or clipboard history.
- Application exclusions.
- Copying Plain Clip's name, icon, or bundled assets.
