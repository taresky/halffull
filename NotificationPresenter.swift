import Cocoa
import UserNotifications

/// Thin wrapper around `UNUserNotificationCenter`.
///
/// **Permission posture:** we deliberately do NOT request notification
/// authorization at launch. A brand-new install pops zero permission
/// dialogs — the only system prompt the user sees is Accessibility, and
/// that's only triggered when they actively try to use the hotkey or click
/// "Open Settings…" in the permission banner.
///
/// Notification authorization is requested LAZILY, and only when the user
/// explicitly toggles "Show notifications" ON in app settings. If they
/// never touch the toggle (default = on, but no system grant yet),
/// `notify(...)` quietly no-ops — the `add()` call silently fails when the
/// process hasn't been granted notification permission.
final class NotificationPresenter: NSObject {

    static let shared = NotificationPresenter()
    private override init() {
        super.init()
        // Delegate is wired up so banners show even when the main window is
        // foreground — has no permission implications.
        UNUserNotificationCenter.current().delegate = self
    }

    /// Post a transient notification.
    /// - No-op if the user disabled notifications in app settings.
    /// - Silent no-op if the system hasn't granted notification permission
    ///   (we don't want a permission prompt to appear mid-conversion).
    func notify(title: String, body: String) {
        guard PreferencesStore.shared.showNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// Explicitly request the user's permission to show notifications.
    /// Call this only in a user-initiated context — e.g. when they toggle
    /// the in-app "Show notifications" preference ON for the first time.
    /// Safe to call repeatedly; the system shows its dialog at most once,
    /// then returns the cached answer.
    func requestAuthorization(_ completion: @escaping (Bool) -> Void = { _ in }) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }
}

extension NotificationPresenter: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
