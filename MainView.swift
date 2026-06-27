import SwiftUI
import Cocoa

/// Single visible window of halfFull. Pure settings + about — no in-app converter.
/// The product itself is the global hotkey; this window is purely how you configure
/// and identify it.
struct MainView: View {

    @ObservedObject var prefs = PreferencesStore.shared
    @State private var axTrusted = AccessibilityHelper.shared.isTrusted
    @State private var axPollTimer: Timer?
    @State private var launchAtLoginToggle: Bool = LaunchAtLoginManager.isEnabled

    private let twitterURL = URL(string: "https://x.com/taresky")!
    // Placeholder — replace once the public source URL is decided.
    private let sourceURL  = URL(string: "https://github.com/taresky/halffull")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                permissionRow
                Divider()
                hotkeySection
                Divider()
                settingsSection
                Divider()
                aboutSection
            }
            .padding(24)
        }
        .frame(width: 460, height: 620)
        .onAppear {
            launchAtLoginToggle = LaunchAtLoginManager.isEnabled
            startAXPolling()
        }
        .onDisappear { stopAXPolling() }
    }

    // MARK: - Hero (icon + name + tagline)

    private var hero: some View {
        HStack(spacing: 16) {
            ZStack {
                // Off-white "paper" with the aA wordmark — matches the .icns
                // visual identity so the window mirrors what the user sees in
                // the Dock and on the landing page.
                LinearGradient(colors: [Color(red: 1.00, green: 1.00, blue: 1.00),
                                        Color(red: 0.92, green: 0.92, blue: 0.94)],
                               startPoint: .top, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack(spacing: 0) {
                    Text("a").font(.system(size: 30, weight: .heavy))
                    Text("A").font(.system(size: 44, weight: .heavy))
                }
                .foregroundStyle(Color(red: 0.05, green: 0.05, blue: 0.08))
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(Bundle.main.appName)
                    .font(.title2).fontWeight(.semibold)
                Text(NSLocalizedString("hero.tagline",
                                       value: "Switch text width with one keystroke.",
                                       comment: ""))
                    .font(.callout).foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Permission status

    /// Three banner states:
    ///   • `granted`  — green, AX permission is live, app is ready.
    ///   • `staleGrant` — amber-red, "you granted before but TCC lost it after an
    ///                   update; click ONE button and we'll fix it." This is the
    ///                   classic ad-hoc-signed update breakage. The single
    ///                   "Recover Permission" button runs `tccutil reset` + re-prompt.
    ///   • `freshNeed` — orange, "you haven't granted yet, here's how" — for
    ///                   first-time users.
    private enum PermissionState { case granted, staleGrant, freshNeed }

    private var permissionState: PermissionState {
        if axTrusted { return .granted }
        return prefs.hasGrantedAXBefore ? .staleGrant : .freshNeed
    }

    @ViewBuilder private var permissionRow: some View {
        let state = permissionState
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: bannerIcon(state))
                    .foregroundStyle(bannerIconColor(state))
                VStack(alignment: .leading, spacing: 1) {
                    Text(bannerTitle(state))
                        .font(.callout).fontWeight(.medium)
                    Text(bannerSubtitle(state))
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            switch state {
            case .granted:
                EmptyView()
            case .staleGrant:
                // ONE button — the recovery flow. We run tccutil reset, relaunch
                // the app, and the fresh process auto-re-prompts. User just toggles
                // the entry on once in System Settings and is done.
                HStack(spacing: 8) {
                    Button(NSLocalizedString("permission.recover",
                                             value: "Recover Permission",
                                             comment: "")) {
                        AccessibilityHelper.shared.resetAndRelaunch()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button(NSLocalizedString("permission.recheck",
                                             value: "Re-check",
                                             comment: "")) {
                        axTrusted = AccessibilityHelper.shared.isTrusted
                    }
                    Spacer()
                }
                .padding(.leading, 30)
            case .freshNeed:
                HStack(spacing: 8) {
                    Button(NSLocalizedString("permission.openSettings",
                                             value: "Open Settings…",
                                             comment: "")) {
                        AccessibilityHelper.shared.ensureTrustedPrompt()
                        AccessibilityHelper.shared.openAccessibilitySettings()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button(NSLocalizedString("permission.recheck",
                                             value: "Re-check",
                                             comment: "")) {
                        axTrusted = AccessibilityHelper.shared.isTrusted
                    }
                    Spacer()
                }
                .padding(.leading, 30)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(bannerBackground(state))
        )
    }

    private func bannerIcon(_ s: PermissionState) -> String {
        switch s {
        case .granted:     return "checkmark.seal.fill"
        case .staleGrant:  return "arrow.triangle.2.circlepath.circle.fill"
        case .freshNeed:   return "exclamationmark.triangle.fill"
        }
    }
    private func bannerIconColor(_ s: PermissionState) -> Color {
        switch s {
        case .granted:     return .green
        case .staleGrant:  return .orange
        case .freshNeed:   return .orange
        }
    }
    private func bannerTitle(_ s: PermissionState) -> String {
        switch s {
        case .granted:
            return NSLocalizedString("permission.granted",
                                     value: "Accessibility granted", comment: "")
        case .staleGrant:
            return NSLocalizedString("permission.stale.title",
                                     value: "Permission was reset by an update",
                                     comment: "")
        case .freshNeed:
            return NSLocalizedString("permission.required",
                                     value: "Accessibility permission required",
                                     comment: "")
        }
    }
    private func bannerSubtitle(_ s: PermissionState) -> String {
        switch s {
        case .granted:
            return String(format: NSLocalizedString("permission.readyHint",
                                                   value: "Press %@ inside any text field.",
                                                   comment: ""), hotkeyLabel)
        case .staleGrant:
            return NSLocalizedString("permission.stale.hint",
                                     value: "macOS dropped the previous grant when halfFull was updated. Click Recover Permission — we'll reset and re-prompt automatically.",
                                     comment: "")
        case .freshNeed:
            return NSLocalizedString("permission.requiredHint",
                                     value: "halfFull needs Accessibility to detect the focused text field.",
                                     comment: "")
        }
    }
    private func bannerBackground(_ s: PermissionState) -> Color {
        switch s {
        case .granted:     return Color.green.opacity(0.08)
        case .staleGrant:  return Color.orange.opacity(0.12)
        case .freshNeed:   return Color.orange.opacity(0.12)
        }
    }

    private var hotkeyLabel: String {
        ModifierTranslator.symbolicDescription(carbonModifiers: prefs.hotKeyCarbonModifiers,
                                               keyCode: prefs.hotKeyKeyCode)
    }

    // MARK: - Hotkey

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(NSLocalizedString("section.hotkey", value: "Hotkey", comment: ""))
            Text(NSLocalizedString("prefs.hotkey.intro",
                                   value: "Press the keys you want to bind. Must include ⌘, ⌃, or ⌥.",
                                   comment: ""))
                .font(.caption).foregroundColor(.secondary)
            HotKeyRecorderView(prefs: prefs)
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(NSLocalizedString("section.settings", value: "Settings", comment: ""))

            row(NSLocalizedString("prefs.direction", value: "Default direction", comment: "")) {
                Picker("", selection: Binding(get: { prefs.conversionDirection },
                                              set: { prefs.conversionDirection = $0 })) {
                    ForEach(ConversionDirection.allCases) { Text($0.localizedName).tag($0) }
                }
                .labelsHidden().frame(width: 180)
            }

            row(NSLocalizedString("prefs.scope", value: "Scope", comment: "")) {
                Picker("", selection: Binding(get: { prefs.conversionScope },
                                              set: { prefs.conversionScope = $0 })) {
                    ForEach(ConversionScope.allCases) { Text($0.localizedName).tag($0) }
                }
                .labelsHidden().frame(width: 180)
            }

            Toggle(NSLocalizedString("prefs.convertSpace",
                                     value: "Convert space to ideographic (U+3000)",
                                     comment: ""),
                   isOn: Binding(get: { prefs.convertSpaceToIdeographic },
                                 set: { prefs.convertSpaceToIdeographic = $0 }))
            Toggle(NSLocalizedString("prefs.restoreClipboard",
                                     value: "Restore clipboard after fallback paste",
                                     comment: ""),
                   isOn: Binding(get: { prefs.restoreClipboard },
                                 set: { prefs.restoreClipboard = $0 }))
            Toggle(NSLocalizedString("prefs.playSound",
                                     value: "Play sound on success",
                                     comment: ""),
                   isOn: Binding(get: { prefs.playSoundOnSuccess },
                                 set: { prefs.playSoundOnSuccess = $0 }))
            Toggle(NSLocalizedString("prefs.notifications",
                                     value: "Show notifications",
                                     comment: ""),
                   isOn: Binding(get: { prefs.showNotifications },
                                 set: { newValue in
                                     prefs.showNotifications = newValue
                                     // Lazy permission request: only prompt when the user
                                     // actively opts in. If they already granted (or denied)
                                     // before, this call is a no-op.
                                     if newValue {
                                         NotificationPresenter.shared.requestAuthorization()
                                     }
                                 }))
            Toggle(NSLocalizedString("prefs.launchAtLogin",
                                     value: "Launch at login",
                                     comment: ""),
                   isOn: Binding(get: { launchAtLoginToggle },
                                 set: { newValue in
                                     _ = LaunchAtLoginManager.setEnabled(newValue)
                                     launchAtLoginToggle = LaunchAtLoginManager.isEnabled
                                     prefs.launchAtLogin = launchAtLoginToggle
                                 }))
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(NSLocalizedString("section.about", value: "About", comment: ""))

            HStack {
                Text(String(format: NSLocalizedString("about.version",
                                                     value: "Version %@ (%@)",
                                                     comment: ""),
                            Bundle.main.shortVersion, Bundle.main.buildNumber))
                    .font(.callout).foregroundColor(.secondary)
                Spacer()
            }

            HStack(spacing: 12) {
                Link(destination: twitterURL) {
                    Label("Twitter @taresky", systemImage: "bird")
                }
                Link(destination: sourceURL) {
                    Label("Source", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            .font(.callout)

            Text(NSLocalizedString("about.copyright",
                                   value: "© 2026 Taresky. PolyForm Noncommercial 1.0.0.",
                                   comment: ""))
                .font(.footnote).foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.subheadline).fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    /// Two-column row: label on the left, content on the right.
    private func row<Content: View>(_ label: String,
                                    @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
            Spacer()
            content()
        }
    }

    // MARK: - AX polling

    private func startAXPolling() {
        axPollTimer?.invalidate()
        // Initial sticky-bit prime: if AX is already granted at window open,
        // record that we *have* been trusted in the past.
        if AccessibilityHelper.shared.isTrusted { prefs.hasGrantedAXBefore = true }
        axPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let now = AccessibilityHelper.shared.isTrusted
            if now != axTrusted { axTrusted = now }
            // Sticky bit — once we observe a granted state, flag it forever so
            // future stale-grant cases can be detected and recovered without
            // the user having to know what `tccutil` is.
            if now { prefs.hasGrantedAXBefore = true }
        }
    }

    private func stopAXPolling() {
        axPollTimer?.invalidate()
        axPollTimer = nil
    }
}

extension Bundle {
    var appName: String {
        (object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "halfFull"
    }
    var shortVersion: String {
        (object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0"
    }
    var buildNumber: String {
        (object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
    }
}
