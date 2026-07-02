# "Show in menu bar" toggle — design

Date: 2026-07-02
Status: approved (user confirmed revised design after adversarial multi-agent review)

## Requirement

Add a "Show in menu bar" setting. Default checked. When unchecked, the menu-bar
icon is hidden immediately; the app keeps running (hotkey + conversion fully
functional). With the icon hidden, the way to open the main window (settings)
is to open the application again from Finder/Launchpad/Spotlight.

Decisions made by the user:
- **No warning UI** when unchecking — no alert, no caption. Final.
- The pre-existing login-launch misdetection fix (touchpoint 5) is in scope.

## Design

Mechanism: keep `StatusBarController` and its `NSStatusItem` alive; toggle
`statusItem.isVisible` only. Never destroy/recreate the item.

### Touchpoints

1. **PreferencesStore.swift** — new key `behavior.showMenuBarIcon`, registered
   default `true`. New property `showMenuBarIcon` following the existing toggle
   pattern (`objectWillChange.send()` then `defaults.set`). The setter also
   posts `PreferencesStore.menuBarIconChangedNotification`
   (`Notification.Name("FWCMenuBarIconChanged")`), mirroring the
   `hotKeyChangedNotification` pattern, so AppKit code reacts without Combine.

2. **StatusBarController.swift** — in `init`, set
   `statusItem.isVisible = PreferencesStore.shared.showMenuBarIcon`.
   Observe `menuBarIconChangedNotification`; on change, re-sync `isVisible`.
   The unconditional init assignment is load-bearing: AppKit persists
   `isVisible` in its own UserDefaults key (per auto-generated autosaveName),
   and assigning from our pref at every launch keeps the app's pref the single
   source of truth. Keep a comment saying so.

3. **MainView.swift** — add a Toggle "Show in menu bar" in the settings section
   next to "Launch at login", bound directly to `prefs.showMenuBarIcon`.
   Localization key `prefs.showMenuBarIcon`. No caption.

4. **Info.plist** — delete the `NSSupportsAutomaticTermination` key.
   Rationale (high-severity review finding): with the icon hidden and the
   window closed the app has zero visible surfaces, which under the
   automatic-termination contract makes it eligible to be silently SIGKILLed
   (sudden termination is also enabled, so no delegate callback). The global
   Carbon hotkey dies with the process and nothing relaunches it until next
   login — contradicting the feature's premise. A global-hotkey utility gains
   nothing from automatic termination. `NSSupportsSuddenTermination` stays
   (it only affects logout/shutdown speed).

5. **halfFullApp.swift** — replace the bare uptime heuristic in
   `shouldOpenMainWindowOnLaunch()` with the real launch-reason signal:
   read `NSAppleEventManager.shared().currentAppleEvent` inside
   `applicationDidFinishLaunching`; treat the launch as a login launch only
   if the event is `kAEOpenApplication` with
   `paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue ==
   keyAELaunchedAsLogInItem` (works with SMAppService login items).
   Keep the existing `uptime < 90s && login-item registered` heuristic only
   as a fallback when the Apple Event is unavailable.
   Rationale (medium-severity review finding): the heuristic misclassifies a
   manual launch within 90s of boot as a login launch; today the always-visible
   icon covers that hole, but with the icon hidden the user would see nothing
   at all — breaking the feature's only window-recovery path. A blanket
   "always show window when icon hidden" was considered and rejected: it would
   pop the settings window at every login for hidden-icon + launch-at-login
   users.

6. **Localizable.xcstrings** — add `prefs.showMenuBarIcon` with `en`
   ("Show in menu bar") and `zh-Hans` ("在菜单栏显示") string units, matching
   how `prefs.launchAtLogin` is catalogued.

### Window recovery path (existing code, verified)

- Icon hidden, app running, user opens the app again → macOS delivers the
  reopen event to the running instance → `applicationShouldHandleReopen`
  (`hasVisibleWindows == false`) → `showMainWindow()`.
- Icon hidden, app not running, manual launch → `shouldOpenMainWindowOnLaunch()`
  returns true (with touchpoint 5, reliably) → window shows.
- Login launch → silent, invisible, hotkey active. Intended.

### Edge cases (reviewed, no action needed)

- Existing users upgrading get default `true` (registered default; icon stays).
- Toggling has no interaction with conversion in flight, notifications, sound,
  or clipboard restore — none depend on the status item.
- ⌘-drag removal of the item is impossible: `behavior` is not set, items are
  non-removable by default.

## Verification

- `xcodebuild build` + existing unit tests pass.
- Manual: toggle off → icon disappears immediately; reopen app from Finder →
  window appears; toggle on → icon reappears; relaunch → states persist.
- Post-implementation adversarial diff review (multi-agent).
