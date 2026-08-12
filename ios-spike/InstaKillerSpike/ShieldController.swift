import Foundation
import FamilyControls
import ManagedSettings
import SwiftUI

/// The four things P0 has to prove, and nothing else.
@MainActor
final class ShieldController: ObservableObject {

    @Published var authorization: AuthorizationStatus = AuthorizationCenter.shared.authorizationStatus
    @Published var selection = FamilyActivitySelection()
    @Published var isShielded = false
    @Published var lastError: String?

    private let store = ManagedSettingsStore(named: .instaKiller)

    init() {
        if let saved = SharedStore.loadSelection() {
            selection = saved
        }
        refreshShieldState()
    }

    // MARK: - Q1: does authorization succeed on this device?

    func requestAuthorization() async {
        lastError = nil
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            // Most common causes, in the order you will hit them:
            //   - running on the Simulator (unsupported, always fails)
            //   - the family-controls entitlement is missing from the app target
            //   - the Apple ID on the device is a child account managed by a parent
            lastError = "Authorization failed: \(error.localizedDescription)"
        }
        authorization = AuthorizationCenter.shared.authorizationStatus
    }

    // MARK: - Q2: does the picker return usable tokens?

    /// Total things selected. Note that apps, categories and web domains are three
    /// separate sets — counting only `applicationTokens` reports "0 blocked" when the
    /// user picked a whole category, which is a real block. Count all three.
    var selectedCount: Int {
        selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
    }

    func persistSelection() {
        SharedStore.saveSelection(selection)
    }

    // MARK: - Q3: does assigning tokens actually block the app?

    func applyShield() {
        lastError = nil
        persistSelection()

        // Assigning an *empty* set is not the same as assigning nil. An empty set is a
        // valid "shield exactly nothing" instruction that looks identical to a working
        // shield from the outside. nil is how you clear it.
        store.shield.applications = selection.applicationTokens.isEmpty
            ? nil
            : selection.applicationTokens

        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)

        if #available(iOS 26.5, *) {
            store.isActive = true
        }

        refreshShieldState()
    }

    func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        refreshShieldState()
    }

    /// The permit, reduced to its smallest form. P1 replaces the manual re-shield with a
    /// `DeviceActivitySchedule` + `intervalWillEndWarning`; see DECISIONS.md D-005.
    func liftShieldForGrant() {
        if #available(iOS 26.5, *) {
            store.isActive = false
        } else {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
        }
        refreshShieldState()
    }

    private func refreshShieldState() {
        if #available(iOS 26.5, *), store.isActive == false {
            isShielded = false
            return
        }
        isShielded = (store.shield.applications?.isEmpty == false)
            || (store.shield.applicationCategories != nil)
    }

    // MARK: - Spike readout

    var appGroupOK: Bool { SharedStore.defaults != nil }
    var lastShieldAction: String? { SharedStore.lastShieldAction }
}
