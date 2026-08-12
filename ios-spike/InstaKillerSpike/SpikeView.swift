import SwiftUI
import FamilyControls

/// Deliberately ugly. This is a diagnostic panel, not the product — the Permit Office
/// design system arrives in P2. Every row here maps to a checklist line in
/// `docs/P0_SPIKE.md`, so a screenshot of this screen is the P0 report.
struct SpikeView: View {
    @ObservedObject var controller: ShieldController
    @State private var pickerPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Environment") {
                    Row("iOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                    Row("App Group", ok: controller.appGroupOK,
                        value: controller.appGroupOK ? SharedStore.appGroupID : "NOT CONFIGURED")
                    Row(".openParentalControlsApp",
                        ok: isOpenParentAvailable,
                        value: isOpenParentAvailable ? "available (iOS 26.5+)" : "unavailable — Shortcuts fallback required")
                    Row("Submenu buttons",
                        ok: isSubmenuAvailable,
                        value: isSubmenuAvailable ? "available (iOS 26.4+)" : "unavailable")
                }

                Section("1 — Authorization") {
                    Row("Status", ok: controller.authorization == .approved,
                        value: String(describing: controller.authorization))
                    Button("Request authorization") {
                        Task { await controller.requestAuthorization() }
                    }
                    if controller.authorization == .denied {
                        Text("Denied. Settings → Screen Time → App & Website Activity must be on, then delete and reinstall this build.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("2 — Selection") {
                    Row("Apps", value: "\(controller.selection.applicationTokens.count)")
                    Row("Categories", value: "\(controller.selection.categoryTokens.count)")
                    Row("Web domains", value: "\(controller.selection.webDomainTokens.count)")
                    Button("Present the picker") { pickerPresented = true }
                        .disabled(controller.authorization != .approved)

                    // Proof of C-3: iOS will draw the name and icon, we cannot. If this
                    // list renders and the count above is non-zero, tokens are real.
                    if !controller.selection.applicationTokens.isEmpty {
                        ForEach(Array(controller.selection.applicationTokens), id: \.self) { token in
                            Label(token)
                        }
                    }
                }

                Section("3 — Shield") {
                    Row("Applied", ok: controller.isShielded,
                        value: controller.isShielded ? "yes" : "no")
                    Button("Apply shield") { controller.applyShield() }
                        .disabled(controller.selectedCount == 0)
                    Button("Lift (simulate a permit)") { controller.liftShieldForGrant() }
                    Button("Clear everything", role: .destructive) { controller.clearShield() }
                }

                Section("4 — Did the shield extension run?") {
                    Text(controller.lastShieldAction ?? "No shield action recorded yet.")
                        .font(.footnote.monospaced())
                        .foregroundStyle(controller.lastShieldAction == nil ? .secondary : .primary)
                }

                if let error = controller.lastError {
                    Section("Error") {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("P0 spike")
            .familyActivityPicker(isPresented: $pickerPresented, selection: $controller.selection)
            .onChange(of: controller.selection) { _, _ in controller.persistSelection() }
        }
    }

    private var isOpenParentAvailable: Bool {
        if #available(iOS 26.5, *) { return true } else { return false }
    }

    private var isSubmenuAvailable: Bool {
        if #available(iOS 26.4, *) { return true } else { return false }
    }
}

private struct Row: View {
    let label: String
    var ok: Bool?
    let value: String

    init(_ label: String, ok: Bool? = nil, value: String) {
        self.label = label
        self.ok = ok
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if let ok { Text(ok ? "✅" : "❌") }
            Text(label)
            Spacer()
            Text(value)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
