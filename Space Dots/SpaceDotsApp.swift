import SwiftUI

@main
struct SpaceDotsApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup(id: "MainWindow") {
            ContentView()
                .environment(appModel)
        }
        // An invisible placeholder: the experience itself opens in the
        // immersive space. The window only grows to show a retry.
        .defaultSize(width: 80, height: 80)
        // The portal draws the complete panel surface. A standard visionOS
        // window adds its own glass backing behind it, visible from the side
        // as a second, detached panel.
        .windowStyle(.plain)
        .windowResizability(.automatic)
        .restorationBehavior(.disabled)
        .persistentSystemOverlays(.hidden)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceWasDismissedBySystem = false
                    appModel.immersiveExperienceAssetsPrepared = false
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    let wasRequestedByApp = appModel.immersiveCloseRequestInFlight
                    appModel.immersiveExperienceAssetsPrepared = false
                    appModel.immersiveSpaceState = .closed
                    appModel.immersiveCloseRequestID = nil
                    appModel.immersiveCloseRequestInFlight = false
                    if !wasRequestedByApp && appModel.mainWindowIsOpen {
                        AppTrace.mark("IMMERSIVE system dismissal; closing main window")
                        appModel.immersiveSpaceWasDismissedBySystem = true
                    }
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
        // The user's real hands are passthrough hands. In the mixed style the
        // system composites them by depth: they show in front of the panel and
        // models when nearer, and disappear behind them when farther.
        .upperLimbVisibility(.visible)
    }
}
