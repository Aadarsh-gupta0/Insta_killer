import SwiftUI
import FamilyControls

@main
struct InstaKillerSpikeApp: App {
    @StateObject private var controller = ShieldController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            SpikeView(controller: controller)
                .onChange(of: scenePhase) { _, phase in
                    // The shield extension runs in another process. Anything it wrote
                    // only becomes visible to us when we come back to the foreground —
                    // which is also exactly when `.openParentalControlsApp` lands us here.
                    if phase == .active {
                        controller.objectWillChange.send()
                    }
                }
        }
    }
}
