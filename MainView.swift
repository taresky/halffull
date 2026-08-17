import SwiftUI
import Cocoa

/// Single visible window of halfFull. Pure settings + about — no in-app converter.
/// The product itself is the global hotkey; this window is purely how you configure
/// and identify it.
struct MainView: View {

    @ObservedObject var prefs = PreferencesStore.shared
    @State private var trustState = AccessibilityHelper.shared.refreshTrustState()
    @State private var axPollTimer: Timer?
    @State private var launchAtLoginToggle: Bool = LaunchAtLoginManager.isEnabled
    @State private var selectedTarget: TargetMode = .focusedText

    private let twitterURL = URL(string: "https://x.com/taresky")!
    // Placeholder — replace once the public source URL is decided.
    private let sourceURL  = URL(string: "https://github.com/taresky/halffull")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                Divider()
                targetPicker
                if selectedTarget == .focusedText {
                    permissionRow
                }
                hotkeySection
                Divider()
                targetSettingsSection
                Divider()
                sharedSettingsSection
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
                                       value: "Transform focused text or clean the clipboard.",
                                       comment: ""))
                    .font(.callout).foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Permission status

    @ViewBuilder private var permissionRow: some View {
        let state = trustState
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
                        trustState = AccessibilityHelper.shared.refreshTrustState()
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
                        trustState = AccessibilityHelper.shared.refreshTrustState()
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

    private func bannerIcon(_ s: TrustState) -> String {
        switch s {
        case .granted:     return "checkmark.seal.fill"
        case .staleGrant:  return "arrow.triangle.2.circlepath.circle.fill"
        case .freshNeed:   return "exclamationmark.triangle.fill"
        }
    }
    private func bannerIconColor(_ s: TrustState) -> Color {
        switch s {
        case .granted:     return .green
        case .staleGrant:  return .orange
        case .freshNeed:   return .orange
        }
    }
    private func bannerTitle(_ s: TrustState) -> String {
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
    private func bannerSubtitle(_ s: TrustState) -> String {
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
    private func bannerBackground(_ s: TrustState) -> Color {
        switch s {
        case .granted:     return Color.green.opacity(0.08)
        case .staleGrant:  return Color.orange.opacity(0.12)
        case .freshNeed:   return Color.orange.opacity(0.12)
        }
    }

    private var hotkeyLabel: String {
        prefs.hotKey(for: .focusedText).symbolicDescription
    }

    // MARK: - Target

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(NSLocalizedString("section.target", value: "Target", comment: ""))
            Picker("", selection: $selectedTarget) {
                Text(NSLocalizedString("target.focusedText",
                                       value: "Focused Text", comment: ""))
                    .tag(TargetMode.focusedText)
                Text(NSLocalizedString("target.clipboard",
                                       value: "Clipboard", comment: ""))
                    .tag(TargetMode.clipboard)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - Hotkey

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(NSLocalizedString("section.hotkey", value: "Hotkey", comment: ""))
            Text(NSLocalizedString("prefs.hotkey.intro",
                                   value: "Press the keys you want to bind. Must include ⌘, ⌃, or ⌥.",
                                   comment: ""))
                .font(.caption).foregroundColor(.secondary)
            HotKeyRecorderView(prefs: prefs, mode: selectedTarget)
        }
    }

    // MARK: - Settings

    @ViewBuilder private var targetSettingsSection: some View {
        switch selectedTarget {
        case .focusedText:
            focusedTextSettingsSection
        case .clipboard:
            plainClipSettingsSection
        }
    }

    private var focusedTextSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(NSLocalizedString("section.focusedTextSettings",
                                            value: "Focused Text Settings", comment: ""))

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
        }
    }

    private var plainClipSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(NSLocalizedString("section.clipboardSettings",
                                            value: "Clipboard Settings", comment: ""))

            Text(NSLocalizedString("plainClip.intro",
                                   value: "Always removes rich formatting. Optional cleanup runs in the order shown.",
                                   comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle(NSLocalizedString("plainClip.trimTrailingLineWhitespace",
                                     value: "Remove trailing spaces and tabs from lines", comment: ""),
                   isOn: Binding(get: { prefs.plainClipTrimTrailingLineWhitespace },
                                 set: { prefs.plainClipTrimTrailingLineWhitespace = $0 }))
            Toggle(NSLocalizedString("plainClip.trimLeadingLineWhitespace",
                                     value: "Remove leading spaces and tabs from lines", comment: ""),
                   isOn: Binding(get: { prefs.plainClipTrimLeadingLineWhitespace },
                                 set: { prefs.plainClipTrimLeadingLineWhitespace = $0 }))
            Toggle(NSLocalizedString("plainClip.removeInvisibleCharacters",
                                     value: "Remove invisible control characters", comment: ""),
                   isOn: Binding(get: { prefs.plainClipRemoveInvisibleCharacters },
                                 set: { prefs.plainClipRemoveInvisibleCharacters = $0 }))
            Toggle(NSLocalizedString("plainClip.removeLineBreaks",
                                     value: "Remove line breaks", comment: ""),
                   isOn: Binding(get: { prefs.plainClipRemoveLineBreaks },
                                 set: { prefs.plainClipRemoveLineBreaks = $0 }))
            Toggle(NSLocalizedString("plainClip.normalizeUnicode",
                                     value: "Normalize Unicode (NFC)", comment: ""),
                   isOn: Binding(get: { prefs.plainClipNormalizeUnicode },
                                 set: { prefs.plainClipNormalizeUnicode = $0 }))
            Toggle(NSLocalizedString("plainClip.replaceTabs",
                                     value: "Replace tabs with spaces", comment: ""),
                   isOn: Binding(get: { prefs.plainClipReplaceTabs },
                                 set: { prefs.plainClipReplaceTabs = $0 }))
            Toggle(NSLocalizedString("plainClip.collapseSpaces",
                                     value: "Collapse consecutive spaces", comment: ""),
                   isOn: Binding(get: { prefs.plainClipCollapseSpaces },
                                 set: { prefs.plainClipCollapseSpaces = $0 }))
            Toggle(NSLocalizedString("plainClip.removeBlankLines",
                                     value: "Remove blank lines", comment: ""),
                   isOn: Binding(get: { prefs.plainClipRemoveBlankLines },
                                 set: { prefs.plainClipRemoveBlankLines = $0 }))
            Toggle(NSLocalizedString("plainClip.straightenQuotes",
                                     value: "Replace smart quotes with straight quotes", comment: ""),
                   isOn: Binding(get: { prefs.plainClipStraightenQuotes },
                                 set: { prefs.plainClipStraightenQuotes = $0 }))
            Toggle(NSLocalizedString("plainClip.convertToASCII",
                                     value: "Convert supported characters to ASCII (preserve others)",
                                     comment: ""),
                   isOn: Binding(get: { prefs.plainClipConvertToASCII },
                                 set: { prefs.plainClipConvertToASCII = $0 }))
            Toggle(NSLocalizedString("plainClip.trimWholeString",
                                     value: "Trim surrounding whitespace", comment: ""),
                   isOn: Binding(get: { prefs.plainClipTrimWholeString },
                                 set: { prefs.plainClipTrimWholeString = $0 }))

            Divider()

            Toggle(NSLocalizedString("plainClip.pasteAfterCleaning",
                                     value: "Paste automatically after cleaning", comment: ""),
                   isOn: Binding(get: { prefs.plainClipPasteAfterCleaning },
                                 set: { prefs.plainClipPasteAfterCleaning = $0 }))
            Text(NSLocalizedString("plainClip.pastePermissionHint",
                                   value: "macOS may request permission the first time automatic paste is used.",
                                   comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var sharedSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(NSLocalizedString("section.appSettings",
                                            value: "App Settings", comment: ""))

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
            Toggle(NSLocalizedString("prefs.showMenuBarIcon",
                                     value: "Show in menu bar",
                                     comment: ""),
                   isOn: Binding(get: { prefs.showMenuBarIcon },
                                 set: { prefs.showMenuBarIcon = $0 }))
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
        trustState = AccessibilityHelper.shared.refreshTrustState()
        axPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let state = AccessibilityHelper.shared.refreshTrustState()
            if state != trustState { trustState = state }
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
