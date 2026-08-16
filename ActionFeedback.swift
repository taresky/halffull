import AppKit

/// Shared success feedback for both target modes.
enum ActionFeedback {
    static func playSuccessSoundIfEnabled() {
        guard PreferencesStore.shared.playSoundOnSuccess else { return }
        successSound?.play()
    }

    /// Keep the sound alive until AppKit has finished playback.
    private static let successSound = NSSound(named: NSSound.Name("Pop"))
}
