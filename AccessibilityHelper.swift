import Cocoa

/// Wraps the AX trust check + System Settings deep link.
/// The "prompt" variant triggers the OS's one-time built-in dialog; we use it
/// only on the first launch so we don't pop the system sheet on every check.
final class AccessibilityHelper {
    static let shared = AccessibilityHelper()
    private init() {}

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

    /// Prompting check — shows the system "wants to control your computer" sheet
    /// once. After the user dismisses it, subsequent calls fall through silently.
    @discardableResult
    func ensureTrustedPrompt() -> Bool {
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
    func relaunchSelf() {
        guard let bundlePath = Bundle.main.bundleURL.path as NSString? else { NSApp.terminate(nil); return }
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", bundlePath as String]
        try? task.run()
        // Give launchctl a moment to register the new process before we exit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
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
