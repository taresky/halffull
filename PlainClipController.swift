import AppKit
import CoreGraphics

/// Imperative shell for one user-requested clipboard cleanup.
final class PlainClipController {
    static let shared = PlainClipController()
    private init() {}

    func trigger(
        optionsOverride: PlainTextCleaner.Options? = nil,
        pasteAfterCleaning pasteOverride: Bool? = nil,
        completion: (() -> Void)? = nil
    ) {
        let prefs = PreferencesStore.shared
        let options = optionsOverride ?? prefs.plainClipOptions
        let shouldPaste = pasteOverride ?? prefs.plainClipPasteAfterCleaning

        switch ClipboardPlainifier.plainify(.general, options: options) {
        case .success:
            ActionFeedback.playSuccessSoundIfEnabled()
            guard shouldPaste else {
                completion?()
                return
            }
            paste(completion: completion)

        case .noText:
            NSSound.beep()
            NotificationPresenter.shared.notify(
                title: NSLocalizedString("plainClip.notify.noText.title",
                                         value: "No text on the clipboard", comment: ""),
                body: NSLocalizedString("plainClip.notify.noText.body",
                                        value: "Copy some text, then try again.", comment: ""))
            completion?()

        case .clipboardChanged:
            NotificationPresenter.shared.notify(
                title: NSLocalizedString("plainClip.notify.changed.title",
                                         value: "Clipboard changed", comment: ""),
                body: NSLocalizedString("plainClip.notify.changed.body",
                                        value: "Newer clipboard content was left untouched.", comment: ""))
            completion?()

        case .writeFailed:
            NSSound.beep()
            NotificationPresenter.shared.notify(
                title: NSLocalizedString("plainClip.notify.writeFailed.title",
                                         value: "Couldn't clean the clipboard", comment: ""),
                body: NSLocalizedString("plainClip.notify.writeFailed.body",
                                        value: "The pasteboard rejected the cleaned text.", comment: ""))
            completion?()
        }
    }

    private func paste(completion: (() -> Void)?) {
        let isAllowed = CGPreflightPostEventAccess() || CGRequestPostEventAccess()
        guard isAllowed else {
            NotificationPresenter.shared.notify(
                title: NSLocalizedString("plainClip.notify.pastePermission.title",
                                         value: "Clipboard cleaned", comment: ""),
                body: NSLocalizedString("plainClip.notify.pastePermission.body",
                                        value: "Allow input control to paste automatically.", comment: ""))
            completion?()
            return
        }

        // Let the global-hotkey/menu event fully unwind before sending Command-V
        // to whichever app still owns keyboard focus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            KeyboardSimulator.press(.v, modifiers: .maskCommand)
            completion?()
        }
    }
}
