import Cocoa

/// The three permission states the app reacts to. Both the settings banner and
/// the launch-time recovery flow key off this — so the derivation lives in one
/// place instead of being re-computed in `MainView` and the `AppDelegate`.
enum TrustState: Equatable {
    /// AX permission is live.
    case granted
    /// Granted before, but TCC lost the grant (typical after an ad-hoc-signed
    /// update gives the app a new CDHash). The recovery flow handles this.
    case staleGrant
    /// Never granted — a first-time user.
    case freshNeed

    /// Pure derivation. `hasGrantedBefore` is the sticky bit that separates a
    /// fresh install from a lost-grant-after-update.
    static func derive(isTrusted: Bool, hasGrantedBefore: Bool) -> TrustState {
        if isTrusted { return .granted }
        return hasGrantedBefore ? .staleGrant : .freshNeed
    }
}

/// Wraps the AX trust check + System Settings deep link.
/// The "prompt" variant triggers the OS's one-time built-in dialog; we use it
/// only on the first launch so we don't pop the system sheet on every check.
final class AccessibilityHelper {
    static let shared = AccessibilityHelper()
    private init() {}

    /// Process-local guard: the system sheet should only appear once per
    /// process, but we also refuse to re-call with `prompt: true` after the
    /// first attempt — belt-and-braces against hotkey spam if the OS ever
    /// re-shows the dialog (or if a second halfFull instance is registered).
    private var didRequestPromptThisProcess = false

    /// Silent check — never prompts.
    ///
    /// Uses `AXIsProcessTrustedWithOptions(nil)` rather than `AXIsProcessTrusted()`.
    /// The latter returns a cached value that is *not* invalidated when the user
    /// flips the toggle in System Settings while the app is running — leading to
    /// the classic "I granted permission but the app still says I didn't" bug.
    /// The "WithOptions" variant talks to the TCC daemon and returns a fresh result.
    var isTrusted: Bool {
        AXIsProcessTrustedWithOptions(nil)
    }

    /// Read live AX trust, maintain the sticky "granted before" bit, and return
    /// the derived `TrustState`. This is the single call both the settings banner
    /// (polled) and the launch-time recovery flow use — neither re-derives the rule.
    @discardableResult
    func refreshTrustState() -> TrustState {
        let trusted = isTrusted
        if trusted { PreferencesStore.shared.hasGrantedAXBefore = true }
        return TrustState.derive(isTrusted: trusted,
                                 hasGrantedBefore: PreferencesStore.shared.hasGrantedAXBefore)
    }

    /// Prompting check — shows the system "wants to control your computer" sheet
    /// at most once per process. After that, subsequent calls only re-check
    /// silently so hotkey presses never re-pop the sheet.
    @discardableResult
    func ensureTrustedPrompt() -> Bool {
        if isTrusted { return true }
        if didRequestPromptThisProcess {
            return isTrusted
        }
        didRequestPromptThisProcess = true
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let opts: NSDictionary = [key: true]
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Open System Settings → Privacy & Security → Accessibility.
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Reset our own TCC Accessibility entry, then RELAUNCH the app so the
    /// system permission prompt can appear cleanly in a fresh process.
    ///
    /// **The "TCC stale grant after ad-hoc update" recovery flow** — every
    /// fresh build of halfFull has a new CDHash (because ad-hoc signing has no
    /// stable identity). TCC still has an entry for `me.taresky.halffull` but
    /// it's keyed to the OLD hash, so `AXIsProcessTrusted` returns false and
    /// ordinary "toggle off/on in System Settings" doesn't fix it — tccd
    /// keeps a ghost row tied to the prior cdhash.
    ///
    /// `tccutil reset Accessibility <bundle-id>` clears the row. Crucially,
    /// `AXIsProcessTrustedWithOptions` caches its result *for the lifetime of
    /// the calling process*, and `kAXTrustedCheckOptionPrompt` only shows the
    /// system dialog ONCE per process — so we **must relaunch** after the
    /// reset for the prompt to reappear. (The prior implementation that re-
    /// called the prompt inline was a silent no-op.)
    ///
    /// User clicks the in-app Recover Permission button →
    ///   1. tccutil reset for our bundle id
    ///   2. open a new instance of /Applications/halfFull.app
    ///   3. terminate ourselves
    ///   4. the new process, in applicationDidFinishLaunching, detects the
    ///      stale-grant state and auto-fires the AX prompt + opens System Settings.
    func resetAndRelaunch() {
        let bid = Bundle.main.bundleIdentifier ?? "me.taresky.halffull"
        let reset = Process()
        reset.launchPath = "/usr/bin/tccutil"
        reset.arguments = ["reset", "Accessibility", bid]
        let stderr = Pipe()
        reset.standardError = stderr
        do {
            try reset.run()
            reset.waitUntilExit()
            let errOut = String(data: stderr.fileHandleForReading.availableData,
                                encoding: .utf8) ?? ""
            if reset.terminationStatus != 0 || errOut.contains("Failed") {
                NSLog("halfFull: tccutil reset stderr — \(errOut)")
            }
        } catch {
            NSLog("halfFull: tccutil reset failed — \(error.localizedDescription)")
        }
        relaunchSelf()
    }

    /// Relaunch ourselves. Used by the in-app "Quit & Relaunch" button when the
    /// user has just granted Accessibility but macOS's TCC cache for the running
    /// process is stale — a fresh process always reads the fresh value.
    ///
    /// **Do not use `open -n`.** That forces a second instance while this one is
    /// still alive; combined with the single-instance handoff in
    /// `AppDelegate`, the new process would see us still running, hand off, and
    /// quit — leaving nothing. Instead: schedule a delayed `open` (no `-n`) and
    /// terminate ourselves first so the relaunch is the only live process.
    func relaunchSelf() {
        let bundlePath = Bundle.main.bundleURL.path
        let escaped = bundlePath.replacingOccurrences(of: "'", with: "'\\''")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // sleep so our process fully exits before LaunchServices re-opens us.
        task.arguments = ["-c", "sleep 0.6; /usr/bin/open '\(escaped)'"]
        do {
            try task.run()
        } catch {
            NSLog("halfFull: relaunch schedule failed — \(error.localizedDescription)")
        }
        NSApp.terminate(nil)
    }

    /// Block-style observer: fires `onTrusted` once permission becomes available.
    /// Polls every 0.5s on the main queue; harmless to leave running indefinitely.
    func observeUntilTrusted(onTrusted: @escaping () -> Void) {
        if isTrusted { onTrusted(); return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if self.isTrusted {
                timer.invalidate()
                onTrusted()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
