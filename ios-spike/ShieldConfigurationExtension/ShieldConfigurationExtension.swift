import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Runs in its own process with a hard memory ceiling, every time a shielded app is
/// opened. Constraints that are not negotiable here:
///
///   - no networking, no image decoding, no database access
///   - no date arithmetic and no policy: read strings, return a struct
///   - never crash. A throwing/OOM extension makes iOS fall back to the default shield,
///     which is survivable, but a crash loop is not.
///
/// Everything it displays was computed by the app and written to the App Group.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration()
    }

    private func makeConfiguration() -> ShieldConfiguration {
        // Permit Office palette. Hard-coded rather than read from the App Group: colours
        // are not user state, and one less read is one less failure mode in here.
        let ledger = UIColor(red: 0.894, green: 0.914, blue: 0.863, alpha: 1)   // #E4E9DC
        let ink    = UIColor(red: 0.086, green: 0.129, blue: 0.110, alpha: 1)   // #16211C
        let stamp  = UIColor(red: 0.702, green: 0.180, blue: 0.106, alpha: 1)   // #B32E1B

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialLight,
            backgroundColor: ledger,
            icon: nil,
            title: ShieldConfiguration.Label(
                text: SharedStore.shieldTitle,
                color: ink
            ),
            subtitle: ShieldConfiguration.Label(
                // FR-8: the user's own declaration, written verbatim by the app.
                text: SharedStore.shieldSubtitle,
                color: ink
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: SharedStore.shieldPrimaryButton,
                color: ledger
            ),
            primaryButtonBackgroundColor: stamp,
            // There is no secondaryButtonBackgroundColor in the API — the secondary
            // button's appearance is entirely system-controlled.
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: SharedStore.shieldSecondaryButton,
                color: ink
            )
        )
    }
}
