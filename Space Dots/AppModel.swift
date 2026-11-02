import AVFoundation
import AVFAudio
import OSLog
import SwiftUI

enum AppTrace {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ProjectHailMary",
        category: "Lifecycle"
    )

    static func mark(_ message: String) {
        logger.notice("[PHM_TRACE] \(message, privacy: .public)")
    }
}

/// AVAudioSession configuration can block while the system changes audio routes.
/// Keep every session change ordered and away from the main actor.
private final class AudioSessionCoordinator: @unchecked Sendable {
    private enum Mode {
        case ambient
        case movie
    }

    private let queue = DispatchQueue(label: "SpaceDots.AudioSession")
    // Accessed only on queue.
    private var appliedMode: Mode?

    func useAmbientAudio() {
        queue.async { [self] in
            let session = AVAudioSession.sharedInstance()
            if case .some(.ambient) = appliedMode {
                try? session.setActive(true)
                return
            }
            do {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                AppTrace.mark("MEDIA audio session deactivation failed: \(error)")
            }
            do {
                try session.setCategory(.ambient, mode: .default, options: [])
                try session.setActive(true)
                appliedMode = .ambient
                AppTrace.mark("MEDIA ambient session active; external music may continue")
            } catch {
                appliedMode = nil
                AppTrace.mark("MEDIA ambient session configuration failed: \(error)")
            }
        }
    }

    func useMovieAudio() {
        queue.async { [self] in
            let session = AVAudioSession.sharedInstance()
            if case .some(.movie) = appliedMode {
                do {
                    try session.setActive(true)
                } catch {
                    AppTrace.mark("THE_MOMENT movie session reactivation failed: \(error)")
                }
                return
            }
            do {
                try session.setCategory(.playback, mode: .moviePlayback, options: [])
                try session.setActive(true)
                appliedMode = .movie
                AppTrace.mark("THE_MOMENT exclusive playback session active")
            } catch {
                // Some routes require deactivation before changing category.
                try? session.setActive(false)
                do {
                    try session.setCategory(.playback, mode: .moviePlayback, options: [])
                    try session.setActive(true)
                    appliedMode = .movie
                    AppTrace.mark("THE_MOMENT movie session used deactivate fallback")
                } catch {
                    appliedMode = nil
                    AppTrace.mark("THE_MOMENT movie session configuration failed: \(error)")
                }
            }
        }
    }
}

enum YouTubePlayerCommand {
    case startFromBeginning
    case play
    case mute
    case pause
    case fadeOutAndPause(milliseconds: Int)
    case seek(seconds: Double, allowSeekAhead: Bool)
    case setVolume(Double)
    case reset

    var startsPlayback: Bool {
        switch self {
        case .startFromBeginning, .play: true
        default: false
        }
    }
}

@MainActor
/// Connects SwiftUI controls on the immersive screen to the screen's own
/// move and resize handling, which lives in the RealityKit scene.
final class PanelHandleBridge {
    var begin: () -> Void = {}
    /// `translation` is in metres in the immersive space, `magnification`
    /// relative to the start of the grab.
    var update: (_ translation: SIMD3<Float>, _ magnification: Float) -> Void = { _, _ in }
    var end: () -> Void = {}
}

@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"

    static let youtubeVideoID = "vppn4gX0eUI"
    static let homeReturnRevealDuration: Double = 0.8
    /// The startup logo's glide from centre to its Home position. The portal
    /// ribbons fade in across it, and the Home copy reveals in its tail.
    static let initialLogoMoveDuration: Double = 4.0
    static let initialHomeRevealDuration: Double = 1.6
    static let particleStartTime: Double = 16.8
    static let activationBoxSwitchTime: Double = 12.5
    private static let effectFadeInDuration: Double = 0.18
    private static let effectFadeDuration: Double = 2.0
    private static let theMomentStopTime: Double = 69.0

    var theMomentTime: Double = 0.0
    var theMomentDuration: Double = 69.0
    var youtubeVideoIsReady = false
    var youtubePlaybackHasStarted = false
    /// How often the video has played through to its end and returned Home.
    /// Leaving early with Close does not count. Kept in UserDefaults, so it
    /// survives relaunches and starts over when the app is reinstalled.
    private(set) var theMomentCompletedViewings = UserDefaults.standard.integer(
        forKey: AppModel.completedViewingsKey
    )
    private static let completedViewingsKey = "theMomentCompletedViewings"
    static let petrovaIndicatorUnlockViewings = 3
    /// The Petrova Indicator only flies in once the video has been watched
    /// in full this many times.
    var petrovaIndicatorIsUnlocked: Bool {
        theMomentCompletedViewings >= Self.petrovaIndicatorUnlockViewings
    }
    var theMomentPlaybackWasRequested = false
    var initialYouTubeStartCommandWasSent = false
    var youtubeVideoErrorCode: Int?
    var theMomentVolume = 0.30
    var theMomentIsPlaying = false
    var effectsActive = false
    var effectsOpacity = 0.0
    var shouldShowStartScreen = true
    var theMomentVideoSurfaceIsReady = false
    var theMomentVideoLayerIsVisible = false
    var youtubeSurfaceReloadID = UUID()
    var theMomentExplanationIsDismissing = false
    var propsAreVisible = true
    var uiEmitterOpacity = 0.0
    var uiEmitterHomeReturnRevealPending = false
    var initialHomeSceneRevealIsAllowed = false
    var startupSequencePhase = StartupSequencePhase.panelFadeIn
    var startupWarningDidAppear = false
    var startupPreloadReleased = false
    var startupHandoffIsActive = false
    var initialStartupCompleted = false
    var immersivePanelIsVisible = false
    var scrubberIsHovered = false
    var scrubberIsEditing = false
    var theMomentControlsAreVisible = false
    var panelManipulationIsActive = false
    /// Lets the video controls move and resize the immersive screen.
    @ObservationIgnored let panelHandle = PanelHandleBridge()
    /// Counts short pinches on the immersive screen that neither moved nor
    /// resized it; each one asks the video controls to appear.
    var panelTapCount = 0
    var canvasShowsFinalHomeState = false
    var mainWindowIsOpen = false
    /// Where the launch window stands in the immersive space, in meters.
    /// The system opens it where the Home View was, so the screen appears
    /// in that direction.
    @ObservationIgnored var mainWindowPositionInImmersiveSpace: SIMD3<Float>?
    var freshLaunchRequired = false
    var immersiveExperienceAssetsPrepared = false
    var mediaExperiencePrepared = false
    var experiencesArePrepared: Bool {
        immersiveExperienceAssetsPrepared && mediaExperiencePrepared
    }
    var immersiveOpenRequestInFlight = false
    var immersiveCloseRequestInFlight = false
    var immersiveSpaceWasDismissedBySystem = false
    var immersiveOpenRequestID: UUID?
    var immersiveCloseRequestID: UUID?
    var astrophageRecenterRequestID: UUID?
    @ObservationIgnored var immersiveOpenTask: Task<Void, Never>?
    @ObservationIgnored private var theMomentReturnTask: Task<Void, Never>?
    @ObservationIgnored private var theMomentAutoPlayTask: Task<Void, Never>?
    @ObservationIgnored private var theMomentTransitionPrewarmed = false
    @ObservationIgnored private var youtubeCommandHandler: ((YouTubePlayerCommand) -> Void)?
    @ObservationIgnored private var youtubeCommandHandlerID: UUID?
    @ObservationIgnored private var pendingYouTubeCommand: YouTubePlayerCommand?
    @ObservationIgnored private let audioSessionCoordinator = AudioSessionCoordinator()

    enum ExperienceScreen: Hashable {
        case menu
        case theMoment
    }
    var experienceScreen = ExperienceScreen.menu

    enum ImmersiveSpaceState: Hashable {
        case closed
        case inTransition
        case open
        case failed
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed

    init() {
        AppTrace.mark("MODEL init begin")
        AppTrace.mark("MODEL YouTube video configured: \(Self.youtubeVideoID)")
        configureExternalMusicCoexistence()
        AppTrace.mark("MODEL init complete")
    }

    func configureTheMomentPlayback() {
        audioSessionCoordinator.useMovieAudio()
    }

    private func maintainExclusiveTheMomentAudioSession() {
        guard experienceScreen == .theMoment, !shouldShowStartScreen else { return }
        audioSessionCoordinator.useMovieAudio()
    }

    func configureExternalMusicCoexistence() {
        audioSessionCoordinator.useAmbientAudio()
    }

    func selectTheMoment() {
        AppTrace.mark("ACTION selectTheMoment begin current=\(experienceScreen)")
        let playerWasPrewarmed = theMomentTransitionPrewarmed
        theMomentTransitionPrewarmed = false
        resetTheMomentPlayback(
            showStartScreen: true,
            resetPlayer: !playerWasPrewarmed
        )
        if !playerWasPrewarmed {
            configureExternalMusicCoexistence()
        }
        theMomentExplanationIsDismissing = false
        experienceScreen = .theMoment
        AppTrace.mark("ACTION selectTheMoment complete current=\(experienceScreen)")
    }

    func prewarmTheMomentTransition() {
        guard !theMomentTransitionPrewarmed else { return }
        theMomentTransitionPrewarmed = true
        configureExternalMusicCoexistence()
        sendYouTubeCommand(.reset)
        AppTrace.mark("THE_MOMENT transition player/audio prewarmed")
    }

    func resetTheMomentPlayback(
        showStartScreen: Bool = true,
        resetPlayer: Bool = true
    ) {
        AppTrace.mark("PLAYER resetTheMomentPlayback begin showStart=\(showStartScreen)")
        theMomentReturnTask?.cancel()
        theMomentReturnTask = nil
        theMomentAutoPlayTask?.cancel()
        theMomentAutoPlayTask = nil
        theMomentVideoSurfaceIsReady = false
        theMomentVideoLayerIsVisible = false
        youtubePlaybackHasStarted = false
        theMomentPlaybackWasRequested = false
        initialYouTubeStartCommandWasSent = false
        if resetPlayer {
            youtubeVideoErrorCode = nil
            youtubeVideoIsReady = false
            theMomentDuration = Self.theMomentStopTime
        }
        theMomentExplanationIsDismissing = false
        if resetPlayer {
            sendYouTubeCommand(.reset)
        }
        updateTheMomentState(seconds: 0.0, isPlaying: false)
        shouldShowStartScreen = showStartScreen
        AppTrace.mark("PLAYER resetTheMomentPlayback complete")
    }

    func beginYouTubePreparation() {
        youtubeVideoErrorCode = nil
        youtubeVideoIsReady = false
        youtubePlaybackHasStarted = false
        theMomentPlaybackWasRequested = false
        initialYouTubeStartCommandWasSent = false
        theMomentDuration = Self.theMomentStopTime
        updateTheMomentState(seconds: 0.0, isPlaying: false)
        AppTrace.mark("YOUTUBE preparation requested by Play")
    }

    func startTheMomentPlayback(startImmediately: Bool = false) {
        AppTrace.mark("ACTION startTheMomentPlayback begin")
        theMomentPlaybackWasRequested = true
        experienceScreen = .theMoment
        shouldShowStartScreen = false
        configureTheMomentPlayback()
        AppTrace.mark("THE_MOMENT exclusive playback session requested")
        if startImmediately {
            requestInitialYouTubeStart()
            theMomentIsPlaying = true
            AppTrace.mark("THE_MOMENT direct user play requested")
        }
        theMomentIsPlaying = false
    }

    /// Starts the video once The Moment's surface is visible.
    func startTheMomentVideo() {
        guard experienceScreen == .theMoment,
              !shouldShowStartScreen,
              !youtubePlaybackHasStarted else { return }

        configureTheMomentPlayback()
        requestInitialYouTubeStart()
        theMomentIsPlaying = true
        theMomentAutoPlayTask?.cancel()
        theMomentAutoPlayTask = Task { @MainActor [weak self] in
            for _ in 0..<8 {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled,
                      let self,
                      self.experienceScreen == .theMoment,
                      !self.shouldShowStartScreen,
                      !self.youtubePlaybackHasStarted else { return }
                self.sendYouTubeCommand(.play)
            }
            self?.theMomentAutoPlayTask = nil
        }
        AppTrace.mark("ACTION The Moment video auto-play requested")
    }

    private func requestInitialYouTubeStart() {
        guard theMomentPlaybackWasRequested,
              !initialYouTubeStartCommandWasSent else { return }
        initialYouTubeStartCommandWasSent = true
        sendYouTubeCommand(.startFromBeginning)
        AppTrace.mark("YOUTUBE explicit playback start requested from zero")
    }

    private func stopTheMomentAtLimit() {
        guard experienceScreen == .theMoment,
              !shouldShowStartScreen,
              theMomentReturnTask == nil else { return }

        AppTrace.mark("ACTION The Moment 1:09 limit fade begin")
        theMomentAutoPlayTask?.cancel()
        theMomentAutoPlayTask = nil
        theMomentIsPlaying = false
        theMomentVideoLayerIsVisible = false
        theMomentExplanationIsDismissing = true
        sendYouTubeCommand(.fadeOutAndPause(milliseconds: 450))

        theMomentReturnTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled,
                  let self,
                  self.experienceScreen == .theMoment,
                  !self.shouldShowStartScreen else { return }
            self.sendYouTubeCommand(.reset)
            self.recordCompletedViewing()
            self.returnToModeMenu()
        }
    }

    func markTheMomentVideoSurfaceReady() {
        guard experienceScreen == .theMoment,
              !shouldShowStartScreen,
              !theMomentVideoSurfaceIsReady else { return }
        theMomentVideoSurfaceIsReady = true
        // Align the immersive oval with where the viewer looks now the video
        // is visible, rather than when the start button was pressed.
        requestAstrophageRecenter()
        AppTrace.mark("THE_MOMENT visible paused surface ready")
    }

    func returnToModeMenu() {
        AppTrace.mark("ACTION returnToModeMenu begin current=\(experienceScreen)")
        let isReturningFromExperience = !shouldShowStartScreen
        if isReturningFromExperience {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                uiEmitterOpacity = 0.0
                uiEmitterHomeReturnRevealPending = true
            }
        }
        resetTheMomentPlayback(showStartScreen: true)
        configureExternalMusicCoexistence()
        experienceScreen = .theMoment
        AppTrace.mark("ACTION returnToModeMenu complete current=\(experienceScreen)")
    }

    private func recordCompletedViewing() {
        theMomentCompletedViewings += 1
        UserDefaults.standard.set(
            theMomentCompletedViewings,
            forKey: Self.completedViewingsKey
        )
    }

    func revealEmitterWithHomeContentIfNeeded() {
        guard uiEmitterHomeReturnRevealPending else { return }
        uiEmitterHomeReturnRevealPending = false
        uiEmitterOpacity = 1.0
    }

    func markFreshLaunchRequired() {
        AppTrace.mark("LIFECYCLE native close received current=\(experienceScreen)")
        freshLaunchRequired = true
        suspendMediaForWindowClose()
    }

    func resetForNextLaunch() {
        AppTrace.mark("LIFECYCLE resetForNextLaunch begin current=\(experienceScreen)")

        resetTheMomentPlayback(showStartScreen: true)
        configureExternalMusicCoexistence()

        experienceScreen = .menu
        theMomentTransitionPrewarmed = false
        immersiveExperienceAssetsPrepared = false
        mediaExperiencePrepared = false
        propsAreVisible = true
        uiEmitterOpacity = 0.0
        uiEmitterHomeReturnRevealPending = false
        initialHomeSceneRevealIsAllowed = false
        startupSequencePhase = .panelFadeIn
        startupWarningDidAppear = false
        startupPreloadReleased = false
        startupHandoffIsActive = false
        initialStartupCompleted = false
        immersivePanelIsVisible = false
        scrubberIsHovered = false
        scrubberIsEditing = false
        theMomentControlsAreVisible = false
        panelManipulationIsActive = false
        theMomentExplanationIsDismissing = false
        freshLaunchRequired = false

        AppTrace.mark("LIFECYCLE resetForNextLaunch complete current=\(experienceScreen)")
    }

    func suspendMediaForWindowClose() {
        sendYouTubeCommand(.pause)
    }

    var activationBoxIsActivated: Bool {
        switch experienceScreen {
        case .theMoment:
            return theMomentPlaybackWasRequested
                && !shouldShowStartScreen
                && theMomentTime >= Self.activationBoxSwitchTime
        case .menu:
            return false
        }
    }

    func toggleTheMomentPlayback() {
        guard experienceScreen == .theMoment,
              !shouldShowStartScreen else { return }

        if theMomentIsPlaying {
            sendYouTubeCommand(.pause)
            theMomentIsPlaying = false
            maintainExclusiveTheMomentAudioSession()
        } else {
            requestAstrophageRecenter()
            configureTheMomentPlayback()
            sendYouTubeCommand(.play)
            theMomentIsPlaying = true
        }
    }

    func pauseTheMomentForScrubbing() {
        guard experienceScreen == .theMoment else { return }
        sendYouTubeCommand(.pause)
        theMomentIsPlaying = false
        maintainExclusiveTheMomentAudioSession()
    }

    func seekTheMoment(to seconds: Double) {
        guard experienceScreen == .theMoment else { return }
        let clampedSeconds = min(max(seconds, 0.0), theMomentDuration)
        sendYouTubeCommand(.seek(seconds: clampedSeconds, allowSeekAhead: true))
        updateTheMomentState(seconds: clampedSeconds, isPlaying: theMomentIsPlaying)
    }

    func previewTheMomentSeek(to seconds: Double) {
        guard experienceScreen == .theMoment else { return }
        let clampedSeconds = min(max(seconds, 0.0), theMomentDuration)
        sendYouTubeCommand(.seek(seconds: clampedSeconds, allowSeekAhead: false))
        updateTheMomentState(seconds: clampedSeconds, isPlaying: false)
    }

    func finishTheMomentScrubbing(to seconds: Double, resumePlayback: Bool) {
        guard experienceScreen == .theMoment else { return }
        let clampedSeconds = min(max(seconds, 0.0), theMomentDuration)
        updateTheMomentState(seconds: clampedSeconds, isPlaying: false)
        sendYouTubeCommand(.seek(seconds: clampedSeconds, allowSeekAhead: true))
        maintainExclusiveTheMomentAudioSession()
        if resumePlayback, !shouldShowStartScreen {
            sendYouTubeCommand(.play)
            theMomentIsPlaying = true
        }
    }

    func skipTheMoment(by seconds: Double) {
        seekTheMoment(to: theMomentTime + seconds)
    }

    func setTheMomentVolume(_ volume: Double) {
        let clampedVolume = min(max(volume, 0.0), 1.0)
        theMomentVolume = clampedVolume
        sendYouTubeCommand(.setVolume(clampedVolume))
    }

    func attachYouTubeCommandHandler(
        id: UUID,
        _ handler: @escaping (YouTubePlayerCommand) -> Void
    ) {
        youtubeCommandHandlerID = id
        youtubeCommandHandler = handler
        // Apply the preload lock before any queued command. Sending mute
        // after an explicit start would cancel that start in the web player.
        handler(.mute)
        if let pendingYouTubeCommand {
            self.pendingYouTubeCommand = nil
            if pendingYouTubeCommand.startsPlayback,
               !canStartTheMomentPlayback {
                AppTrace.mark("PLAYER stale YouTube play suppressed outside The Moment")
                return
            }
            handler(pendingYouTubeCommand)
        }
    }

    func detachYouTubeCommandHandler(id: UUID) {
        guard youtubeCommandHandlerID == id else { return }
        youtubeCommandHandlerID = nil
        youtubeCommandHandler = nil
    }

    func youtubePlayerDidBecomeReady(duration: Double) {
        if duration.isFinite, duration > 0.0 {
            theMomentDuration = min(duration, Self.theMomentStopTime)
        }
        youtubeVideoErrorCode = nil
        youtubeVideoIsReady = true
        mediaExperiencePrepared = true
        AppTrace.mark("YOUTUBE ready duration=\(theMomentDuration)")
    }

    func youtubePlayerDidUpdate(
        time: Double,
        duration: Double,
        state: Int
    ) {
        if duration.isFinite, duration > 0.0 {
            if !youtubeVideoIsReady {
                youtubePlayerDidBecomeReady(duration: duration)
            } else {
                let effectiveDuration = min(duration, Self.theMomentStopTime)
                if abs(theMomentDuration - effectiveDuration) > 0.05 {
                    theMomentDuration = effectiveDuration
                }
            }
        }

        guard theMomentPlaybackWasRequested,
              !shouldShowStartScreen,
              experienceScreen == .theMoment else {
            if state == 1 {
                sendYouTubeCommand(.pause)
                AppTrace.mark("YOUTUBE unsolicited preload playback paused")
            }
            updateTheMomentState(seconds: 0.0, isPlaying: false)
            return
        }

        let isPlaying = state == 1
        if isPlaying,
           !shouldShowStartScreen,
           !youtubePlaybackHasStarted {
            youtubePlaybackHasStarted = true
            theMomentAutoPlayTask?.cancel()
            theMomentAutoPlayTask = nil
            AppTrace.mark("THE_MOMENT room dimming activated with YouTube playback start")
        }

        if isPlaying,
           time >= Self.theMomentStopTime,
           experienceScreen == .theMoment,
           !shouldShowStartScreen {
            AppTrace.mark("YOUTUBE stop limit reached at 1:09; returning Home")
            stopTheMomentAtLimit()
            return
        }
        updateTheMomentState(seconds: time, isPlaying: isPlaying)

        if state == 0,
           experienceScreen == .theMoment,
           !shouldShowStartScreen,
           theMomentReturnTask == nil {
            AppTrace.mark("YOUTUBE playback ended")
            recordCompletedViewing()
            returnToModeMenu()
        }
    }

    func youtubePlayerDidFail(errorCode: Int) {
        youtubeVideoErrorCode = errorCode
        youtubeVideoIsReady = false
        mediaExperiencePrepared = true
        theMomentIsPlaying = false
        AppTrace.mark("YOUTUBE error code=\(errorCode)")
    }

    private func sendYouTubeCommand(_ command: YouTubePlayerCommand) {
        if command.startsPlayback && !canStartTheMomentPlayback {
            AppTrace.mark("PLAYER YouTube play suppressed outside active The Moment")
            pendingYouTubeCommand = nil
            return
        }
        guard let youtubeCommandHandler else {
            pendingYouTubeCommand = command
            return
        }
        youtubeCommandHandler(command)
    }

    private var canStartTheMomentPlayback: Bool {
        experienceScreen == .theMoment
            && !shouldShowStartScreen
            && theMomentPlaybackWasRequested
    }

    private func requestAstrophageRecenter() {
        let requestID = UUID()
        astrophageRecenterRequestID = requestID
        AppTrace.mark("ASTROPHAGE recenter requested id=\(requestID)")
    }

    private func updateTheMomentState(seconds: Double, isPlaying: Bool) {
        let safeSeconds = seconds.isFinite ? max(0.0, seconds) : 0.0
        let activeSeconds = experienceScreen == .theMoment
            && !shouldShowStartScreen
            && theMomentPlaybackWasRequested ? safeSeconds : 0.0
        if abs(theMomentTime - activeSeconds) > 0.001 {
            theMomentTime = activeSeconds
        }

        guard experienceScreen == .theMoment,
              !shouldShowStartScreen,
              theMomentPlaybackWasRequested else {
            if theMomentIsPlaying {
                theMomentIsPlaying = false
            }
            if effectsActive { effectsActive = false }
            if effectsOpacity != 0.0 { effectsOpacity = 0.0 }
            return
        }

        let activationOpacity = effectActivationOpacity(at: activeSeconds)
        let endFadeOpacity = endFadeOpacity(at: activeSeconds)
        let newEffectsOpacity = activationOpacity * endFadeOpacity
        let newEffectsActive = newEffectsOpacity > 0.001
        if abs(effectsOpacity - newEffectsOpacity) > 0.0005 {
            effectsOpacity = newEffectsOpacity
        }
        if effectsActive != newEffectsActive {
            effectsActive = newEffectsActive
        }
        if theMomentIsPlaying != isPlaying {
            theMomentIsPlaying = isPlaying
        }
    }

    private func endFadeOpacity(at seconds: Double) -> Double {
        guard theMomentDuration.isFinite,
              theMomentDuration > 1.0 else {
            return 1.0
        }

        let normalized = min(
            max((theMomentDuration - seconds) / Self.effectFadeDuration, 0.0),
            1.0
        )
        return normalized * normalized * (3.0 - 2.0 * normalized)
    }

    private func effectActivationOpacity(at seconds: Double) -> Double {
        guard seconds >= Self.particleStartTime else { return 0.0 }

        let normalized = min(
            max((seconds - Self.particleStartTime) / Self.effectFadeInDuration, 0.0),
            1.0
        )
        let eased = 1.0 - pow(1.0 - normalized, 3.0)
        return eased
    }

}
