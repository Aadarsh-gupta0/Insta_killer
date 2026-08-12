import ManagedSettings
import UserNotifications

/// The most important 60 lines in the spike.
///
/// This is where we find out whether the kickoff brief's central architectural claim —
/// "a shield button cannot launch our app, therefore the Gate must live behind a
/// user-created Shortcuts automation" — is still true. On iOS 26.5 it is not:
/// `ShieldActionResponse.openParentalControlsApp` exists and does exactly that.
///
/// See DECISIONS.md D-004.
class ShieldActionExtension: ShieldActionDelegate {

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, subject: "application", completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, subject: "webDomain", completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, subject: "category", completionHandler: completionHandler)
    }

    private func respond(
        to action: ShieldAction,
        subject: String,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        // Proof-of-life for the P0 readout. In P1 this becomes an append to the shared
        // SQLite event log (FR-7).
        SharedStore.recordShieldAction("\(subject): \(describe(action))")

        switch action {
        case .primaryButtonPressed:
            // "Close". The attempt ends here. This is the outcome we want most of the time.
            completionHandler(.close)

        case .secondaryButtonPressed:
            // "Request a permit" — hand the user to the Gate rather than deciding here.
            openGate(completionHandler: completionHandler)

        // iOS 26.4+ submenu items, only reachable when the shield config sets
        // `secondaryButtonSubmenuItems`. Up to three; iOS adds Cancel itself.
        case .firstSecondarySubmenuItemPressed,
             .secondSecondarySubmenuItemPressed,
             .thirdSecondarySubmenuItemPressed:
            openGate(completionHandler: completionHandler)

        @unknown default:
            completionHandler(.close)
        }
    }

    /// Three rungs, strongest first. Which one you get depends entirely on the OS.
    private func openGate(completionHandler: @escaping (ShieldActionResponse) -> Void) {
        if #available(iOS 26.5, *) {
            // Rung 1: iOS foregrounds our app directly. No extra tap, nothing for the
            // user to have deleted, nothing to have been swallowed by a Focus mode.
            completionHandler(.openParentalControlsApp)
            return
        }

        // Rung 2: post a notification and hope the user taps it. Genuinely unreliable —
        // it needs notification authorization, it can be held back by a Focus mode, and
        // Apple Intelligence notification summaries can delay delivery by minutes.
        // Never present this as equivalent to rung 1 in the UI.
        let content = UNMutableNotificationContent()
        content.title = "Permit request"
        content.body = "Tap to open Insta_killer and state your reason."
        content.sound = nil
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "gate.open.\(UUID().uuidString)",
            content: content,
            trigger: nil // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { _ in
            // Close either way. If the notification failed we have rung 3 — the
            // Shortcuts automation — and if that is gone too, the block simply holds,
            // which is the correct failure direction.
            completionHandler(.close)
        }
    }

    private func describe(_ action: ShieldAction) -> String {
        switch action {
        case .primaryButtonPressed: return "primaryButtonPressed"
        case .secondaryButtonPressed: return "secondaryButtonPressed"
        case .firstSecondarySubmenuItemPressed: return "submenu[0]"
        case .secondSecondarySubmenuItemPressed: return "submenu[1]"
        case .thirdSecondarySubmenuItemPressed: return "submenu[2]"
        @unknown default: return "unknown"
        }
    }
}
