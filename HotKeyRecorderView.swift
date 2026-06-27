import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Captures a single global hotkey by listening for a local key event while focused.
/// While "recording", an `NSEvent` local monitor intercepts the next keyDown with
/// at least one modifier (otherwise we'd swallow normal typing) and returns nil so
/// the host text field never sees it.
struct HotKeyRecorderView: View {
    @ObservedObject var prefs: PreferencesStore
    @State private var recording = false
    @State private var monitor: Any?
    // Cleanup when the Preferences window resigns key. macOS SwiftUI TabView keeps
    // sibling tabs alive (no onDisappear when switching to a sibling), so we'd otherwise
    // leave the monitor installed and swallow ⌘W / ⌘, / etc.
    @State private var resignObserver: NSObjectProtocol?

    var body: some View {
        HStack(spacing: 12) {
            Text(currentLabel)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 140, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(recording ? Color.accentColor : Color.secondary.opacity(0.4),
                                      lineWidth: recording ? 2 : 1)
                )

            Button(recording
                   ? NSLocalizedString("hotkey.recordingButton", value: "Press a key…", comment: "")
                   : NSLocalizedString("hotkey.recordButton",    value: "Record", comment: "")) {
                if recording { stop() } else { start() }
            }
            .keyboardShortcut(.defaultAction)

            Button(NSLocalizedString("hotkey.reset", value: "Reset", comment: "")) {
                prefs.setHotKey(keyCode: UInt32(kVK_ANSI_F),
                                carbonModifiers: UInt32(optionKey))
            }
        }
        .onAppear { startResignObserver() }
        .onDisappear { stop(); stopResignObserver() }
    }

    private var currentLabel: String {
        ModifierTranslator.symbolicDescription(carbonModifiers: prefs.hotKeyCarbonModifiers,
                                               keyCode: prefs.hotKeyKeyCode)
    }

    private func start() {
        recording = true
        // .keyDown only. We require at least one non-shift modifier so the recorder
        // can't capture plain letters — that would brick the user's typing.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Defensive: if the monitor outlives `recording` (TabView keeps siblings alive),
            // fall through and let the keyDown propagate normally instead of swallowing it.
            guard recording else { return event }
            let cocoa = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let nonShiftModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
            if !cocoa.intersection(nonShiftModifiers).isEmpty {
                let carbon = ModifierTranslator.carbonFlags(from: cocoa)
                prefs.setHotKey(keyCode: UInt32(event.keyCode), carbonModifiers: carbon)
                stop()
                return nil
            }
            // Escape cancels recording without changing the binding.
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            return event
        }
    }

    private func stop() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func startResignObserver() {
        guard resignObserver == nil else { return }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main) { _ in stop() }
    }

    private func stopResignObserver() {
        if let obs = resignObserver {
            NotificationCenter.default.removeObserver(obs)
            resignObserver = nil
        }
    }
}
