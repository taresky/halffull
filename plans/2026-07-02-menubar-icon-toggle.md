# "Show in menu bar" Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A default-on "Show in menu bar" setting; unchecking hides the `NSStatusItem` while the app (hotkey, conversion) keeps running; re-opening the app is the reliable way back to the settings window.

**Architecture:** Keep `StatusBarController`'s `NSStatusItem` alive and toggle only `isVisible`, synced from a new `PreferencesStore` pref via a dedicated `Notification.Name` (mirrors the existing hotkey pattern). Two enabling fixes ride along: remove `NSSupportsAutomaticTermination` (so macOS can't silently reap the now-invisible app), and detect login-item launches from the launching Apple Event instead of the uptime guess (so a manual open always shows the window).

**Tech Stack:** Swift, AppKit (pure `NSApplicationDelegate` app), SwiftUI settings view, XCTest, hand-maintained `project.pbxproj` (objectVersion 56, fake sequential UUIDs `8A123456...`).

**Spec:** `specs/2026-07-02-menubar-icon-toggle-design.md` (user-approved).

## Global Constraints

- **No warning UI** when unchecking the toggle — no alert, no caption. User decision, final.
- Pref key literal: `behavior.showMenuBarIcon`, registered default `true` (never `set` as default).
- Notification name literal: `FWCMenuBarIconChanged`.
- Localization key: `prefs.showMenuBarIcon` — en "Show in menu bar", zh-Hans "在菜单栏显示".
- Never call `NSStatusBar.removeStatusItem` — visibility only.
- `NSSupportsSuddenTermination` stays in Info.plist; only `NSSupportsAutomaticTermination` is removed.
- Build: `xcodebuild -project halfFull.xcodeproj -scheme halfFull -configuration Debug build`
- Test: `xcodebuild -project halfFull.xcodeproj -scheme halfFull test -destination 'platform=macOS'`

---

### Task 1: `LaunchReason` — Apple-Event-based login-launch detection (TDD)

**Files:**
- Create: `LaunchReason.swift` (repo root, like all app sources)
- Create: `Tests/LaunchReasonTests.swift`
- Modify: `halfFull.xcodeproj/project.pbxproj` (4 sections)
- Modify: `halfFullApp.swift:167-175` (`shouldOpenMainWindowOnLaunch`)

**Interfaces:**
- Produces: `LaunchReason.isLoginItemLaunch(event: NSAppleEventDescriptor?, systemUptime: TimeInterval, isLoginItemRegistered: Bool) -> Bool` — pure decision function, no globals, so it's unit-testable. Task 1 is the only consumer wiring it into the AppDelegate.

- [ ] **Step 1: Write the failing tests**

Create `Tests/LaunchReasonTests.swift`:

```swift
import XCTest
import Carbon
@testable import halfFull

final class LaunchReasonTests: XCTestCase {

    // MARK: - Apple Event available (authoritative signal)

    func testOpenEventWithLoginItemFlagIsLoginLaunch() {
        XCTAssertTrue(LaunchReason.isLoginItemLaunch(event: openEvent(loginItem: true),
                                                     systemUptime: 5000,
                                                     isLoginItemRegistered: false))
    }

    func testOpenEventWithoutFlagIsManualEvenRightAfterBoot() {
        // The exact hole the old heuristic had: manual open < 90 s after boot
        // while registered as a login item must still show the window.
        XCTAssertFalse(LaunchReason.isLoginItemLaunch(event: openEvent(loginItem: false),
                                                      systemUptime: 30,
                                                      isLoginItemRegistered: true))
    }

    func testNonOpenEventIsManual() {
        let quit = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEQuitApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        XCTAssertFalse(LaunchReason.isLoginItemLaunch(event: quit,
                                                      systemUptime: 30,
                                                      isLoginItemRegistered: true))
    }

    // MARK: - No event → legacy uptime heuristic

    func testNoEventEarlyUptimeRegisteredFallsBackToLoginHeuristic() {
        XCTAssertTrue(LaunchReason.isLoginItemLaunch(event: nil,
                                                     systemUptime: 30,
                                                     isLoginItemRegistered: true))
    }

    func testNoEventLateUptimeIsManual() {
        XCTAssertFalse(LaunchReason.isLoginItemLaunch(event: nil,
                                                      systemUptime: 300,
                                                      isLoginItemRegistered: true))
    }

    func testNoEventNotRegisteredIsManual() {
        XCTAssertFalse(LaunchReason.isLoginItemLaunch(event: nil,
                                                      systemUptime: 30,
                                                      isLoginItemRegistered: false))
    }

    // MARK: - Helpers

    private func openEvent(loginItem: Bool) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        if loginItem {
            event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)),
                           forKeyword: AEKeyword(keyAEPropData))
        }
        return event
    }
}
```

- [ ] **Step 2: Register both new files in project.pbxproj**

Four edits, following the file's existing style exactly:

In the `PBXBuildFile` section (after the `8A12345601234567A0000050 /* ConversionEngineTests.swift in Sources */` line):

```
		8A12345601234567A0000051 /* LaunchReason.swift in Sources */ = {isa = PBXBuildFile; fileRef = 8A1234560123456700000051 /* LaunchReason.swift */; };
		8A12345601234567A0000052 /* LaunchReasonTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 8A1234560123456700000052 /* LaunchReasonTests.swift */; };
```

In the `PBXFileReference` section (after the `8A1234560123456700000050 /* ConversionEngineTests.swift */` line):

```
		8A1234560123456700000051 /* LaunchReason.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LaunchReason.swift; sourceTree = "<group>"; };
		8A1234560123456700000052 /* LaunchReasonTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LaunchReasonTests.swift; sourceTree = "<group>"; };
```

In the `System` PBXGroup (`8A1234560123456700000222`), add to `children` after `PreferencesStore.swift`:

```
				8A1234560123456700000051 /* LaunchReason.swift */,
```

In the `Tests` PBXGroup (`8A1234560123456700000225`), add to `children`:

```
				8A1234560123456700000052 /* LaunchReasonTests.swift */,
```

In the app target's `PBXSourcesBuildPhase` (the one containing `ConversionEngine.swift in Sources`, around line 286), add:

```
				8A12345601234567A0000051 /* LaunchReason.swift in Sources */,
```

In the test target's `PBXSourcesBuildPhase` (the one containing `ConversionEngineTests.swift in Sources`, around line 307), add:

```
				8A12345601234567A0000052 /* LaunchReasonTests.swift in Sources */,
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodebuild -project halfFull.xcodeproj -scheme halfFull test -destination 'platform=macOS' 2>&1 | tail -20`
Expected: **BUILD FAILURE** — `Build input file cannot be found: .../LaunchReason.swift` (the RED state; the pbxproj references the file but it doesn't exist yet).

- [ ] **Step 4: Write the implementation**

Create `LaunchReason.swift`:

```swift
import Cocoa
import Carbon

/// Decides whether this process launch was initiated by the system as a
/// login item (→ stay silent in the menu bar) rather than by the user
/// (→ show the main window).
///
/// Primary signal: the launching Apple Event. SMAppService login-item
/// launches carry `keyAELaunchedAsLogInItem` in the `kAEOpenApplication`
/// event's `keyAEPropData` parameter — a manual Finder/Spotlight launch
/// produces an `oapp` event WITHOUT that flag, even seconds after login.
///
/// Fallback (no event to inspect): the legacy heuristic — within 90 s of
/// boot AND registered as a login item ⇒ assume login launch.
enum LaunchReason {

    static func isLoginItemLaunch(event: NSAppleEventDescriptor?,
                                  systemUptime: TimeInterval,
                                  isLoginItemRegistered: Bool) -> Bool {
        guard let event else {
            return systemUptime < 90 && isLoginItemRegistered
        }
        guard event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication),
              let propData = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData)) else {
            return false
        }
        return propData.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild -project halfFull.xcodeproj -scheme halfFull test -destination 'platform=macOS' 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **` (all 6 new tests + existing ConversionEngineTests pass).

- [ ] **Step 6: Wire into the AppDelegate**

In `halfFullApp.swift`, replace the body of `shouldOpenMainWindowOnLaunch()` (lines 167-175):

```swift
    private func shouldOpenMainWindowOnLaunch() -> Bool {
        // Login-item launches are detected from the launching Apple Event
        // (keyAELaunchedAsLogInItem) — authoritative, so a manual open right
        // after boot still shows the window. The uptime heuristic only breaks
        // ties when no event is available. See LaunchReason.
        let isLoginLaunch = LaunchReason.isLoginItemLaunch(
            event: NSAppleEventManager.shared().currentAppleEvent,
            systemUptime: ProcessInfo.processInfo.systemUptime,
            isLoginItemRegistered: SMAppService.mainApp.status == .enabled)
        return !isLoginLaunch
    }
```

- [ ] **Step 7: Build to verify**

Run: `xcodebuild -project halfFull.xcodeproj -scheme halfFull -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add LaunchReason.swift Tests/LaunchReasonTests.swift halfFull.xcodeproj/project.pbxproj halfFullApp.swift
git commit -m "fix: detect login-item launches via Apple Event, not uptime guess"
```

---

### Task 2: Pref + status-item visibility + toggle UI + localization

**Files:**
- Modify: `PreferencesStore.swift` (Key enum ~line 31, register ~line 49, new property after `launchAtLogin` ~line 121, new notification name after line 15)
- Modify: `StatusBarController.swift` (init ~line 24, actions ~line 118)
- Modify: `MainView.swift` (settings section, after the launch-at-login Toggle ~line 281)
- Modify: `Localizable.xcstrings`

**Interfaces:**
- Consumes: nothing from Task 1 (independent).
- Produces: `PreferencesStore.shared.showMenuBarIcon: Bool`, `PreferencesStore.menuBarIconChangedNotification: Notification.Name`.

- [ ] **Step 1: Add the preference**

In `PreferencesStore.swift` — after the `hotKeyChangedNotification` declaration (line 15):

```swift
    /// Posted (in addition to `objectWillChange`) when the menu-bar-icon pref
    /// changes, so `StatusBarController` can re-sync without Combine.
    static let menuBarIconChangedNotification = Notification.Name("FWCMenuBarIconChanged")
```

In the `Key` enum, after `launchAtLogin`:

```swift
        static let showMenuBarIcon = "behavior.showMenuBarIcon"
```

In `register(defaults:)`, after `Key.launchAtLogin: false,`:

```swift
            Key.showMenuBarIcon: true,
```

After the `launchAtLogin` property:

```swift
    var showMenuBarIcon: Bool {
        get { defaults.bool(forKey: Key.showMenuBarIcon) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Key.showMenuBarIcon)
            NotificationCenter.default.post(name: Self.menuBarIconChangedNotification, object: nil)
        }
    }
```

- [ ] **Step 2: Sync the status item**

In `StatusBarController.swift` `init`, after `statusItem.menu = buildMenu()`:

```swift
        // Our pref is the single source of truth for visibility. AppKit also
        // persists isVisible under its own defaults key (per autosaveName);
        // this unconditional assignment overrides whatever it restored.
        statusItem.isVisible = PreferencesStore.shared.showMenuBarIcon

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleMenuBarIconChanged),
                                               name: PreferencesStore.menuBarIconChangedNotification,
                                               object: nil)
```

In the `// MARK: - Actions` block, after `handleHotKeyChanged`:

```swift
    @objc private func handleMenuBarIconChanged() {
        statusItem.isVisible = PreferencesStore.shared.showMenuBarIcon
    }
```

- [ ] **Step 3: Add the toggle to the settings UI**

In `MainView.swift`, immediately after the "Launch at login" `Toggle` (ends line 281):

```swift
            Toggle(NSLocalizedString("prefs.showMenuBarIcon",
                                     value: "Show in menu bar",
                                     comment: ""),
                   isOn: Binding(get: { prefs.showMenuBarIcon },
                                 set: { prefs.showMenuBarIcon = $0 }))
```

No caption, no alert (Global Constraints).

- [ ] **Step 4: Add localization entries**

In `Localizable.xcstrings`, insert between the `"prefs.section.conversion"` block and `"prefs.tab.about"` (alphabetical order, matching the file's compact single-line stringUnit style):

```json
    "prefs.showMenuBarIcon" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Show in menu bar" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "在菜单栏显示" } }
      }
    },
```

- [ ] **Step 5: Build and test**

Run: `xcodebuild -project halfFull.xcodeproj -scheme halfFull test -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add PreferencesStore.swift StatusBarController.swift MainView.swift Localizable.xcstrings
git commit -m "feat: add 'Show in menu bar' setting (default on)"
```

---

### Task 3: Stop opting into automatic termination

**Files:**
- Modify: `Info.plist:33-34`

**Interfaces:** none.

- [ ] **Step 1: Remove the key**

Delete exactly these two lines from `Info.plist` (keep `NSSupportsSuddenTermination`):

```xml
    <key>NSSupportsAutomaticTermination</key>
    <true/>
```

Rationale (from the spec): with the icon hidden and the window closed, the app has zero visible surfaces, making it eligible for a silent SIGKILL under the automatic-termination contract — which would kill the global hotkey with no way back until next login.

- [ ] **Step 2: Build**

Run: `xcodebuild -project halfFull.xcodeproj -scheme halfFull -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Info.plist
git commit -m "fix: drop NSSupportsAutomaticTermination — hidden-icon app must not be reaped"
```

---

### Task 4: End-to-end verification

**Files:** none (verification only).

- [ ] **Step 1: Full test suite + clean build**

Run: `xcodebuild -project halfFull.xcodeproj -scheme halfFull test -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 2: Launch the built app and smoke-test the toggle**

Launch the Debug build. Verify, in order:
1. Menu-bar icon visible (default true), settings window opens on manual launch.
2. Uncheck "Show in menu bar" → icon disappears immediately; window stays open; no alert.
3. Close the window (app → accessory, fully invisible). Hotkey still converts text.
4. Open the app again from Finder → settings window reappears (reopen path).
5. Re-check the toggle → icon reappears immediately.
6. Quit, relaunch → icon still visible, pref persisted. Uncheck, quit, relaunch → icon stays hidden, window shows (manual launch).

- [ ] **Step 3: Adversarial diff review**

Run a multi-agent review over `git diff main...HEAD` (or the last 3 commits); fix confirmed findings before finishing.
