import SwiftUI
import UIKit

private struct MainWindowSceneReader: UIViewRepresentable {
    func makeUIView(context: Context) -> MainWindowSceneProbeView {
        let view = MainWindowSceneProbeView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: MainWindowSceneProbeView, context: Context) {}
}

/// Reports where the launch window stands in the immersive space once that
/// space is open.
private struct MainWindowPlacementReader: View {
    @Environment(AppModel.self) private var appModel
    /// Points per meter in the immersive space's coordinate space.
    private static let pointsPerMeter = 1360.0

    var body: some View {
        GeometryReader3D { proxy in
            Color.clear
                .task(id: appModel.immersiveSpaceState) {
                    guard appModel.immersiveSpaceState == .open else {
                        appModel.mainWindowPositionInImmersiveSpace = nil
                        return
                    }
                    // The space's coordinates settle shortly after it opens.
                    for _ in 0..<40 {
                        if let transform = proxy.transform(in: .immersiveSpace) {
                            let center = Point3D(
                                x: proxy.size.width / 2,
                                y: proxy.size.height / 2,
                                z: proxy.size.depth / 2
                            ).applying(transform)
                            let position = SIMD3<Float>(
                                Float(center.x / Self.pointsPerMeter),
                                Float(-center.y / Self.pointsPerMeter),
                                Float(center.z / Self.pointsPerMeter)
                            )
                            if position.x.isFinite, position.y.isFinite,
                               position.z.isFinite {
                                appModel.mainWindowPositionInImmersiveSpace = position
                            }
                        }
                        try? await Task.sleep(for: .milliseconds(50))
                        guard !Task.isCancelled else { return }
                    }
                }
        }
        .allowsHitTesting(false)
    }
}

@MainActor
private final class MainWindowSceneProbeView: UIView {
    static let didResolveNotification = Notification.Name(
        "ProjectHailMary.MainWindowSceneDidResolve"
    )
    private var lastReportedSceneID: ObjectIdentifier?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let windowScene = window?.windowScene else { return }
        let sceneID = ObjectIdentifier(windowScene)
        guard sceneID != lastReportedSceneID else { return }
        lastReportedSceneID = sceneID

        Task { @MainActor [weak windowScene] in
            guard let windowScene else { return }
            NotificationCenter.default.post(
                name: Self.didResolveNotification,
                object: windowScene
            )
        }
    }
}

struct ContentView: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase
    @State private var windowHasBeenActive = false
    @State private var lastRequestedWindowSize = CGSize(width: 80, height: 80)
    @State private var hostingWindowScene: UIWindowScene?
    @State private var startupSequenceTask: Task<Void, Never>?
    @State private var shouldAutoOpenImmersiveSpace = true
    @State private var sceneWasBackgrounded = false
    @State private var systemHomeExitInProgress = false
    @State private var shouldOpenImmersiveSpaceAfterClose = false

    var body: some View {
        ZStack {
            if windowShowsPanel {
                ExperiencePanelView(
                    isImmersiveAttachment: false,
                    retryAction: requestImmersiveSpaceIfNeeded
                )
                .opacity(shouldSuppressFreshLaunchContent ? 0.0 : 1.0)
            } else {
                Color.clear
                    .frame(width: 80, height: 80)
            }
        }
        .allowsHitTesting(windowShowsPanel)
        .background { MainWindowSceneReader() }
        .background { MainWindowPlacementReader() }
        .onReceive(
            NotificationCenter.default.publisher(
                for: MainWindowSceneProbeView.didResolveNotification
            )
        ) { notification in
            guard let scene = notification.object as? UIWindowScene,
                  hostingWindowScene !== scene else { return }
            hostingWindowScene = scene
            guard !(appModel.freshLaunchRequired && !appModel.mainWindowIsOpen) else {
                return
            }
            AppTrace.mark("MAIN hosting UIWindowScene resolved")
            updateMainWindowGeometry()
        }
        .onChange(of: appModel.immersiveSpaceState) { _, state in
            guard shouldOpenImmersiveSpaceAfterClose,
                  state == .closed,
                  appModel.mainWindowIsOpen,
                  scenePhase == .active,
                  shouldAutoOpenImmersiveSpace else { return }
            shouldOpenImmersiveSpaceAfterClose = false
            requestImmersiveSpaceIfNeeded()
        }
        .onChange(of: appModel.immersiveSpaceWasDismissedBySystem) { _, dismissed in
            guard dismissed else { return }

            AppTrace.mark("MAIN consuming system immersive dismissal")
            systemHomeExitInProgress = true
            shouldAutoOpenImmersiveSpace = false
            shouldOpenImmersiveSpaceAfterClose = false
            invalidateOpenRequest()
            appModel.markFreshLaunchRequired()
            appModel.mainWindowIsOpen = false
            appModel.immersiveSpaceWasDismissedBySystem = false
            let windowScene = hostingWindowScene
            Task { @MainActor in
                await Task.yield()
                if let windowScene {
                    UIApplication.shared.requestSceneSessionDestruction(
                        windowScene.session,
                        options: nil
                    )
                } else {
                    dismissWindow(id: "MainWindow")
                }
            }
        }
        .onAppear {
            AppTrace.mark("MAIN window onAppear screen=\(appModel.experienceScreen)")
            systemHomeExitInProgress = false
            let isFreshWindow = !appModel.mainWindowIsOpen
                && appModel.freshLaunchRequired
            if isFreshWindow {
                appModel.initialStartupCompleted = false
                appModel.startupSequencePhase = .panelFadeIn
                appModel.startupWarningDidAppear = false
                appModel.startupPreloadReleased = false
                appModel.startupHandoffIsActive = false
                shouldAutoOpenImmersiveSpace = true
            }
            if !appModel.initialStartupCompleted,
               appModel.experienceScreen == .menu {
                appModel.startupPreloadReleased = false
            }
            if !appModel.mainWindowIsOpen,
               (appModel.freshLaunchRequired
                || appModel.experienceScreen != .menu) {
                appModel.resetForNextLaunch()
            }
            updateMainWindowGeometry()
            appModel.mainWindowIsOpen = true
            windowHasBeenActive = scenePhase == .active
            if appModel.immersiveSpaceState == .inTransition {
                invalidateOpenRequest()
                appModel.immersiveSpaceState = .closed
            } else if appModel.immersiveSpaceState == .failed {
                appModel.immersiveSpaceState = .closed
            }

            recoverFromStaleCloseRequestIfNeeded()
            beginInitialStartupSequenceIfNeeded()
            if shouldAutoOpenImmersiveSpace {
                requestImmersiveSpaceForActiveWindow()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            AppTrace.mark("MAIN scenePhase -> \(String(describing: phase))")
            if phase == .active {
                systemHomeExitInProgress = false
                if sceneWasBackgrounded {
                    shouldAutoOpenImmersiveSpace = true
                    sceneWasBackgrounded = false
                }
                if !appModel.mainWindowIsOpen,
                   appModel.freshLaunchRequired {
                    appModel.resetForNextLaunch()
                }
                appModel.mainWindowIsOpen = true
                windowHasBeenActive = true
                updateMainWindowGeometry()
                recoverFromStaleCloseRequestIfNeeded()
                requestImmersiveSpaceForActiveWindow()
                return
            }

            guard phase == .background, windowHasBeenActive else { return }
            shouldAutoOpenImmersiveSpace = false
            shouldOpenImmersiveSpaceAfterClose = false
            sceneWasBackgrounded = true
            appModel.suspendMediaForWindowClose()
            appModel.mainWindowIsOpen = false
        }
        .onDisappear {
            AppTrace.mark("MAIN window onDisappear")
            startupSequenceTask?.cancel()
            startupSequenceTask = nil
            appModel.startupHandoffIsActive = false
            shouldAutoOpenImmersiveSpace = false
            shouldOpenImmersiveSpaceAfterClose = false
            if systemHomeExitInProgress {
                AppTrace.mark("MAIN window disappeared after Digital Crown exit")
                return
            }
            appModel.markFreshLaunchRequired()
            appModel.mainWindowIsOpen = false
            dismissImmersiveSpaceIfNeeded()
        }
        .onChange(of: appModel.experienceScreen) { oldScreen, newScreen in
            AppTrace.mark("MAIN screen \(oldScreen) -> \(newScreen)")
        }
        .onChange(of: windowShowsPanel) { _, _ in
            updateMainWindowGeometry()
        }
        .onChange(of: appModel.youtubePlaybackHasStarted) { _, hasStarted in
            guard hasStarted else { return }
            AppTrace.mark("MAIN The Moment playback started after surface preparation")
        }
    }

    /// The experience lives in the immersive space from the first frame.
    /// The window is an invisible placeholder unless that space failed and
    /// the window has to offer a retry.
    private var windowShowsPanel: Bool {
        appModel.immersiveSpaceState == .failed
    }

    private var shouldSuppressFreshLaunchContent: Bool {
        appModel.freshLaunchRequired && !appModel.mainWindowIsOpen
    }

    private func beginInitialStartupSequenceIfNeeded() {
        guard !appModel.initialStartupCompleted,
              startupSequenceTask == nil,
              appModel.experienceScreen == .menu,
              appModel.immersiveSpaceState != .failed else { return }

        startupSequenceTask = Task { @MainActor in
            appModel.uiEmitterOpacity = 0.0
            AppTrace.mark("MAIN startup sequence begin")

            // The immersive space may take longer to open on a cold launch.
            // Start the warning clock only after its visual entrance finishes.
            while !Task.isCancelled,
                  !appModel.startupWarningDidAppear,
                  appModel.immersiveSpaceState != .failed {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard !Task.isCancelled else { return }
            guard appModel.startupWarningDidAppear else {
                startupSequenceTask = nil
                return
            }

            // Let the warning finish its fade-in before activating WebKit.
            // The immersive space holds back hand tracking and its models
            // until the warning is fully visible.
            appModel.startupPreloadReleased = true
            AppTrace.mark("MAIN startup warning visible; releasing preload")
            requestImmersiveSpaceForActiveWindow()

            try? await Task.sleep(for: .milliseconds(4_500))
            guard !Task.isCancelled else { return }

            // The first RealityKit/WebKit load can take longer than the normal
            // warning on a cold launch. Keep the warning on screen while that
            // work finishes, so the title hand-off never competes with it.
            if !appModel.experiencesArePrepared {
                AppTrace.mark("MAIN startup assets still loading; warning remains visible")
                while !Task.isCancelled,
                      !appModel.experiencesArePrepared,
                      appModel.immersiveSpaceState != .failed {
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            guard !Task.isCancelled else { return }
            AppTrace.mark(
                "MAIN startup warning preload result prepared=\(appModel.experiencesArePrepared)"
            )

            // Move the player reset and audio-session work into the warning,
            // away from the visible The Moment text/button reveal, and keep
            // the warning up while it settles.
            appModel.prewarmTheMomentTransition()
            try? await Task.sleep(for: .milliseconds(2_050))
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 1.2)) {
                appModel.startupSequencePhase = .warningExiting
            }

            try? await Task.sleep(for: .milliseconds(1_300))
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.65)) {
                appModel.startupSequencePhase = .loading
            }
            // The portal keeps the ribbons hidden until the logo moves and
            // then fades them in on its own clock.
            appModel.uiEmitterOpacity = 1.0

            // Let the loading identity settle at centre before it becomes
            // the Home title inside the portal.
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: AppModel.initialLogoMoveDuration)) {
                appModel.startupSequencePhase = .movingTitle
            }

            // Start The Moment's copy and button in the tail of the logo
            // move, so both reveals reach their endpoints together.
            try? await Task.sleep(
                for: .seconds(
                    AppModel.initialLogoMoveDuration
                        - AppModel.initialHomeRevealDuration
                )
            )
            guard !Task.isCancelled else { return }

            if !appModel.experiencesArePrepared {
                while !Task.isCancelled,
                      !appModel.experiencesArePrepared,
                      appModel.immersiveSpaceState != .failed {
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }

            guard !Task.isCancelled else { return }
            guard appModel.immersiveSpaceState != .failed,
                  appModel.experiencesArePrepared else {
                startupSequenceTask = nil
                return
            }

            AppTrace.mark("MAIN startup assets ready; presenting The Moment")
            appModel.startupHandoffIsActive = true
            appModel.selectTheMoment()
            appModel.initialStartupCompleted = true
            try? await Task.sleep(for: .seconds(AppModel.initialHomeRevealDuration))
            guard !Task.isCancelled else { return }
            appModel.startupHandoffIsActive = false
            appModel.initialHomeSceneRevealIsAllowed = true
            AppTrace.mark("MAIN startup UI handoff complete; home scene reveal released")
            startupSequenceTask = nil
        }
    }

    private func updateMainWindowGeometry() {
        guard let windowScene = activeMainWindowScene else {
            AppTrace.mark("MAIN geometry update deferred: no active UIWindowScene")
            return
        }

        let configuration = windowGeometryConfiguration
        let targetSize = configuration.size
        guard targetSize != lastRequestedWindowSize else {
            AppTrace.mark("MAIN geometry request skipped: already at target")
            return
        }
        requestWindowGeometry(
            scene: windowScene,
            size: targetSize,
            minimumSize: configuration.minimumSize,
            maximumSize: configuration.maximumSize,
            restrictions: configuration.restrictions
        )
        lastRequestedWindowSize = targetSize
        AppTrace.mark("MAIN geometry requested \(Int(targetSize.width))x\(Int(targetSize.height))")
    }

    private struct WindowGeometryConfiguration {
        let size: CGSize
        let minimumSize: CGSize
        let maximumSize: CGSize
        let restrictions: UIWindowScene.ResizingRestrictions
    }

    /// An invisible 80 pt placeholder, or the panel size while the window
    /// offers a retry.
    private var windowGeometryConfiguration: WindowGeometryConfiguration {
        guard windowShowsPanel else {
            let size = CGSize(width: 80, height: 80)
            return WindowGeometryConfiguration(
                size: size,
                minimumSize: size,
                maximumSize: size,
                restrictions: .freeform
            )
        }
        let size = CGSize(width: 1280, height: 720)
        return WindowGeometryConfiguration(
            size: size,
            minimumSize: CGSize(width: 960, height: 540),
            maximumSize: size,
            restrictions: .uniform
        )
    }

    private func requestWindowGeometry(
        scene: UIWindowScene,
        size: CGSize,
        minimumSize: CGSize,
        maximumSize: CGSize,
        restrictions: UIWindowScene.ResizingRestrictions
    ) {
        if let sizeRestrictions = scene.sizeRestrictions {
            sizeRestrictions.minimumSize = minimumSize
            sizeRestrictions.maximumSize = maximumSize
        }

        let preferences = UIWindowScene.GeometryPreferences.Vision(
            size: size,
            minimumSize: minimumSize,
            maximumSize: maximumSize,
            resizingRestrictions: restrictions
        )
        scene.requestGeometryUpdate(preferences) { error in
            AppTrace.mark("MAIN geometry update failed: \(error.localizedDescription)")
        }
    }

    private var activeMainWindowScene: UIWindowScene? {
        if let hostingWindowScene,
           hostingWindowScene.activationState == .foregroundActive {
            return hostingWindowScene
        }

        let foregroundScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        return foregroundScenes.first(where: { scene in
            scene.windows.contains(where: \.isKeyWindow)
        }) ?? foregroundScenes.first
    }

    private func dismissImmersiveSpaceIfNeeded() {
        invalidateOpenRequest()
        appModel.suspendMediaForWindowClose()

        let immersiveSpaceMayBeOpen = appModel.immersiveSpaceState == .open
            || appModel.immersiveSpaceState == .inTransition

        guard immersiveSpaceMayBeOpen,
              !appModel.immersiveCloseRequestInFlight else { return }

        let closeRequestID = UUID()
        appModel.immersiveCloseRequestID = closeRequestID
        appModel.immersiveCloseRequestInFlight = true
    }

    private func recoverFromStaleCloseRequestIfNeeded() {
        guard appModel.immersiveCloseRequestInFlight,
              let closeRequestID = appModel.immersiveCloseRequestID else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard appModel.mainWindowIsOpen,
                  scenePhase == .active,
                  appModel.immersiveCloseRequestID == closeRequestID else { return }

            appModel.immersiveCloseRequestID = nil
            appModel.immersiveCloseRequestInFlight = false
            requestImmersiveSpaceIfNeeded()
        }
    }

    private func requestImmersiveSpaceIfNeeded() {
        guard scenePhase == .active,
              appModel.mainWindowIsOpen,
              shouldAutoOpenImmersiveSpace,
              appModel.immersiveSpaceState == .closed
                || appModel.immersiveSpaceState == .failed,
              !appModel.immersiveOpenRequestInFlight,
              !appModel.immersiveCloseRequestInFlight else { return }

        let requestID = UUID()
        appModel.immersiveOpenRequestID = requestID
        appModel.immersiveOpenRequestInFlight = true
        appModel.immersiveSpaceState = .inTransition
        if !appModel.initialStartupCompleted {
            beginInitialStartupSequenceIfNeeded()
        }
        appModel.immersiveOpenTask = Task { @MainActor in
            await synchronizeImmersiveSpace(requestID: requestID)
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(12))
            guard appModel.immersiveOpenRequestID == requestID,
                  appModel.immersiveSpaceState == .inTransition else { return }
            invalidateOpenRequest()
            appModel.immersiveSpaceState = .failed
        }
    }

    private func requestImmersiveSpaceForActiveWindow() {
        guard scenePhase == .active,
              appModel.mainWindowIsOpen,
              shouldAutoOpenImmersiveSpace else { return }

        if appModel.immersiveCloseRequestInFlight {
            shouldOpenImmersiveSpaceAfterClose = true
            return
        }

        shouldOpenImmersiveSpaceAfterClose = false
        requestImmersiveSpaceIfNeeded()
    }

    private func invalidateOpenRequest() {
        appModel.immersiveOpenRequestID = nil
        appModel.immersiveOpenRequestInFlight = false
        appModel.immersiveOpenTask?.cancel()
        appModel.immersiveOpenTask = nil
    }

    private func synchronizeImmersiveSpace(requestID: UUID) async {
        guard appModel.mainWindowIsOpen,
              scenePhase == .active,
              appModel.immersiveSpaceState == .inTransition,
              appModel.immersiveOpenRequestID == requestID,
              appModel.immersiveOpenRequestInFlight,
              !appModel.immersiveCloseRequestInFlight else { return }

        defer {
            if appModel.immersiveOpenRequestID == requestID {
                appModel.immersiveOpenRequestID = nil
                appModel.immersiveOpenRequestInFlight = false
                appModel.immersiveOpenTask = nil
            }
        }

        var failedAttempts = 0
        while !Task.isCancelled,
              appModel.mainWindowIsOpen,
              scenePhase == .active,
              appModel.immersiveOpenRequestID == requestID {
            switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
            case .opened:
                guard appModel.immersiveOpenRequestID == requestID,
                      appModel.mainWindowIsOpen else { return }
                appModel.immersiveSpaceState = .open
                return
            case .error:
                guard appModel.immersiveOpenRequestID == requestID,
                      appModel.mainWindowIsOpen else { return }
                failedAttempts += 1
                guard failedAttempts < 3 else {
                    appModel.immersiveSpaceState = .failed
                    return
                }
                await dismissImmersiveSpace()
                guard appModel.immersiveOpenRequestID == requestID,
                      appModel.mainWindowIsOpen else { return }
                appModel.immersiveSpaceState = .inTransition
                try? await Task.sleep(for: .milliseconds(400))
            case .userCancelled:
                if appModel.immersiveOpenRequestID == requestID {
                    appModel.immersiveSpaceState = .failed
                }
                return
            @unknown default:
                try? await Task.sleep(for: .seconds(1))
            }
        }

        if appModel.immersiveOpenRequestID == requestID,
           appModel.immersiveSpaceState == .inTransition {
            appModel.immersiveSpaceState = .closed
        }
    }
}

struct ExperiencePanelView: View {
    @Environment(AppModel.self) private var appModel
    let isImmersiveAttachment: Bool
    let retryAction: () -> Void
    @State private var portalFirstFrameIsReady = false

    var body: some View {
        let presentation = PanelPortalPresentation(appModel: appModel)
        ZStack {
            Color.black
                .opacity(isImmersiveAttachment || portalFirstFrameIsReady ? 0 : 1)
                .allowsHitTesting(false)

            if !isImmersiveAttachment {
                AstrophageRibbonPortalView(
                    effectOpacity: presentation.effectOpacity,
                    effectFadeDuration: AppModel.homeReturnRevealDuration,
                    overlay: presentation.overlay,
                    overlayOpacity: presentation.overlayOpacity,
                    overlayFadeDuration: presentation.overlayFadeDuration,
                    prewarmStaticOverlays: appModel.startupPreloadReleased,
                    onReady: { portalFirstFrameIsReady = true }
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(0)
            }

            if appModel.immersiveSpaceState == .failed {
                ImmersiveSpaceFailureView(retryAction: retryAction)
            } else if appModel.immersiveSpaceState == .open {
                // Create the WebView only after the warning's fade-in, so
                // WebKit's process launch cannot make the fade stutter.
                if appModel.startupPreloadReleased {
                    YouTubeVideoSurface(
                        videoID: AppModel.youtubeVideoID,
                        appModel: appModel
                    )
                    .id(appModel.youtubeSurfaceReloadID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(z: isImmersiveAttachment ? 0 : ExperienceUIStyle.portalContentDepthOffset)
                    .opacity(appModel.theMomentVideoLayerIsVisible ? 1.0 : 0.0)
                    .animation(
                        .easeInOut(duration: 0.55),
                        value: appModel.theMomentVideoLayerIsVisible
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(!appModel.theMomentVideoLayerIsVisible)
                    .zIndex(1)
                }

                // The actual The Moment controls stay alive for interaction,
                // but whenever the portal draws the warning, loading, hand-off
                // or Home texture they must not render a second, flickering
                // copy of the title and backdrop behind it.
                TheMomentModePanel(
                    allowStartupPrewarm: appModel.startupPreloadReleased,
                    portalOwnsVisuals: presentation.overlay != .none,
                    isImmersiveAttachment: isImmersiveAttachment
                )
                .allowsHitTesting(appModel.experienceScreen == .theMoment)
                .accessibilityHidden(appModel.experienceScreen != .theMoment)
                .clipped()
                .zIndex(2)
            }
        }
        .frame(
            width: isImmersiveAttachment ? 1280 : nil,
            height: isImmersiveAttachment ? 720 : nil
        )
        .compositingGroup(isEnabled: !isImmersiveAttachment)
        .clipShape(RoundedRectangle(
            cornerRadius: ExperienceUIStyle.panelCornerRadius,
            style: .continuous
        ))
    }
}

enum StartupSequencePhase: Int {
    /// The immersive scene fades the warning panel in on its own clock.
    case panelFadeIn
    case warning
    case warningExiting
    case loading
    case loadingExiting
    case movingTitle
}

@MainActor
struct PanelPortalPresentation {
    let appModel: AppModel

    private var isStarting: Bool {
        !appModel.initialStartupCompleted
            && appModel.experienceScreen == .menu
            && appModel.immersiveSpaceState != .failed
    }

    /// On a movie return, preserve the last visible portal frame behind the
    /// video fade. The existing Home reveal then takes over without a black
    /// interstitial frame.
    var effectOpacity: Double {
        // Keep the centred logo on black. During the move the portal drives
        // the ribbon fade from the logo's own animation clock.
        if isStarting || appModel.startupHandoffIsActive { return 0 }
        return max(
            appModel.uiEmitterOpacity,
            appModel.uiEmitterHomeReturnRevealPending ? 1 : 0
        )
    }

    var overlay: AstrophagePortalOverlay {
        if isStarting || appModel.startupHandoffIsActive {
            switch appModel.startupSequencePhase {
            case .panelFadeIn, .warning, .warningExiting: return .warning
            case .loading, .loadingExiting: return .loading
            case .movingTitle: return .handoff
            }
        }
        if appModel.immersiveSpaceState == .open,
           appModel.experienceScreen == .theMoment,
           appModel.shouldShowStartScreen,
           !appModel.theMomentVideoLayerIsVisible,
           appModel.youtubeVideoErrorCode == nil {
            return .home
        }
        return .none
    }

    var overlayOpacity: Double {
        guard isStarting || appModel.startupHandoffIsActive else {
            return overlay == .none ? 0 : 1
        }
        switch appModel.startupSequencePhase {
        case .panelFadeIn, .warningExiting: return 0
        case .warning, .loading, .loadingExiting, .movingTitle: return 1
        }
    }

    var overlayFadeDuration: Double {
        switch appModel.startupSequencePhase {
        case .warningExiting: return 1.2
        // The logo fades in unhurried, floating in front of the panel.
        case .loading: return 1.4
        default: return 0.65
        }
    }
}

private struct ImmersiveSpaceFailureView: View {

    let retryAction: () -> Void

    var body: some View {
        ZStack {
            startupGradient

            VStack(spacing: 24) {
                Text("The experience could not start.")
                    .font(.system(size: 25, weight: .semibold, design: .default))
                    .foregroundStyle(ExperienceUIStyle.primaryText)

                FeedbackButton(action: retryAction) {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .tint(ExperienceUIStyle.primaryRed)
                .experienceRedButtonHover()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, idealWidth: 960, maxWidth: .infinity,
               minHeight: 400, idealHeight: 540, maxHeight: .infinity)
    }

    private var startupGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.015, green: 0.001, blue: 0.002),
                Color(red: 0.12, green: 0.006, blue: 0.008),
                Color(red: 0.025, green: 0.001, blue: 0.002)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct TheMomentModePanel: View {
    let allowStartupPrewarm: Bool
    let portalOwnsVisuals: Bool
    let isImmersiveAttachment: Bool

    var body: some View {
        TheMomentView(
            allowStartupPrewarm: allowStartupPrewarm,
            portalOwnsVisuals: portalOwnsVisuals,
            isImmersiveAttachment: isImmersiveAttachment
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
