# CONTEXT — halfFull

Ubiquitous language for halfFull, a macOS menu-bar app that switches text between
half-width and full-width forms via a global hotkey. Name concepts with these
terms; don't drift to synonyms.

## Glossary

**Conversion** — turning the text of the focused field between half-width and
full-width forms, in a chosen **direction** and **scope**. The character-level
rules are pure and live in `ConversionEngine`.

**Direction** — `toFullWidth`, `toHalfWidth`, or `smart` (sampled from the text).

**Scope** — which characters convert: `all`, `punctuation`, or `alphanumeric`.

**EditableField** — the text field the user has focused, and how halfFull reads
and rewrites it. A deep module (`EditableField.swift`): callers pass a pure
`transform` and get back an `Outcome`; whether the rewrite used a direct
**Accessibility write** or the **clipboard fallback** is hidden behind its seam.
_Avoid_: "text editor", "AX editor" (the module is broader than the AX path).

**Accessibility write** — the preferred rewrite path: read the selection or
value and set it back through the Accessibility API. Clipboard and focus
untouched, no synthetic keystrokes.

**Clipboard fallback** — the rewrite path used only when an element refuses an
Accessibility write (some Electron / Java / web inputs): synthetic ⌘A/⌘C,
`changeCount` verification, ⌘V, then restore of the user's clipboard. An
implementation detail of `EditableField`, never exposed to callers.

**Outcome** — the caller-visible result of a conversion: `applied`, `noChange`,
`notFocused`, `unreadable`, or `busy`. The controller maps each to a
notification or the success sound.

**HotKey** — the user's global hotkey binding: virtual key code plus Carbon
modifier bits as one value. Formatting and Cocoa/Carbon modifier conversion
belong to this value type. _Avoid_: passing `keyCode` and `carbonModifiers` as
loose pairs.

**Trust** — whether macOS has granted halfFull the Accessibility permission it
needs to inspect and edit the focused field. Owned by `AccessibilityHelper`.

**TrustState** — the three user-facing trust states: `granted`, `staleGrant`, or
`freshNeed`. The pure derivation from live Accessibility trust plus the sticky
`hasGrantedAXBefore` bit lives in one module and is shared by launch-time
recovery and the settings banner.
