import Foundation
import FamilyControls
import ManagedSettings

/// Everything the app and its extensions agree on lives here.
///
/// Add this file to **all three** targets (app, ShieldConfigurationExtension,
/// ShieldActionExtension). Nothing else is shared.
enum SharedStore {

    // Must match the App Group added to every target's Signing & Capabilities.
    static let appGroupID = "group.com.aadarsh.instakiller"

    /// `nil` when the App Group is missing or misspelled on this target.
    ///
    /// Deliberately not falling back to `.standard`: a silent fallback makes a
    /// misconfigured App Group look like working code right up until the extension
    /// reads an empty selection and quietly stops shielding. P0 needs this to be loud.
    static let defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)

    private enum Key {
        static let selection = "selection.v1"
        static let shieldTitle = "shield.title"
        static let shieldSubtitle = "shield.subtitle"
        static let shieldPrimary = "shield.primaryButton"
        static let shieldSecondary = "shield.secondaryButton"
        static let lastShieldAction = "spike.lastShieldAction"
    }

    // MARK: - The selected apps

    static func saveSelection(_ selection: FamilyActivitySelection) {
        guard let defaults else { return }
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: Key.selection)
    }

    static func loadSelection() -> FamilyActivitySelection? {
        guard let defaults, let data = defaults.data(forKey: Key.selection) else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    // MARK: - Shield copy
    //
    // Read by the shield extension, which has a hard memory ceiling and cannot
    // compute anything. Strings only, written by the app.

    static var shieldTitle: String {
        get { defaults?.string(forKey: Key.shieldTitle) ?? "Blocked" }
        set { defaults?.set(newValue, forKey: Key.shieldTitle) }
    }

    static var shieldSubtitle: String {
        get { defaults?.string(forKey: Key.shieldSubtitle) ?? "This app is closed under your own instruction." }
        set { defaults?.set(newValue, forKey: Key.shieldSubtitle) }
    }

    static var shieldPrimaryButton: String {
        get { defaults?.string(forKey: Key.shieldPrimary) ?? "Close" }
        set { defaults?.set(newValue, forKey: Key.shieldPrimary) }
    }

    static var shieldSecondaryButton: String {
        get { defaults?.string(forKey: Key.shieldSecondary) ?? "Request a permit" }
        set { defaults?.set(newValue, forKey: Key.shieldSecondary) }
    }

    // MARK: - Spike instrumentation
    //
    // P0 only. The real build appends to the shared SQLite log (see DECISIONS.md D-001);
    // for the spike a single string is enough to prove the extension ran at all.

    static func recordShieldAction(_ description: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        defaults?.set("\(stamp) — \(description)", forKey: Key.lastShieldAction)
    }

    static var lastShieldAction: String? {
        defaults?.string(forKey: Key.lastShieldAction)
    }
}

extension ManagedSettingsStore.Name {
    /// One named store for the whole product. See DECISIONS.md D-003.
    static let instaKiller = Self("instakiller")
}
