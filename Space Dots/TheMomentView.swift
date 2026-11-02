import Foundation
import QuartzCore
import SwiftUI
import UIKit
import WebKit

private struct TheMomentSlider: View {
    @Binding var value: Double

    let range: ClosedRange<Double>
    let onEditingChanged: (Bool) -> Void
    let accessibilityLabel: String
    let accessibilityValue: (Double) -> String

    @State private var isTracking = false

    private let thumbDiameter: CGFloat = 16
    private let trackHeight: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let usableWidth = max(1, geometry.size.width - thumbDiameter)
            let progress = normalizedValue

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.28))
                    .frame(maxWidth: .infinity)
                    .frame(height: trackHeight)
                    .padding(.horizontal, thumbDiameter / 2)

                Capsule()
                    .fill(.white)
                    .frame(width: max(trackHeight, usableWidth * progress))
                    .frame(height: trackHeight)
                    .padding(.leading, thumbDiameter / 2)

                Circle()
                    .fill(.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .offset(x: usableWidth * progress)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Capsule())
            .hoverEffect(.highlight)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isTracking {
                            isTracking = true
                            onEditingChanged(true)
                        }

                        updateValue(at: gesture.location.x, width: geometry.size.width)
                    }
                    .onEnded { gesture in
                        updateValue(at: gesture.location.x, width: geometry.size.width)
                        isTracking = false
                        onEditingChanged(false)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(Text(accessibilityValue(value)))
        }
        .frame(height: 24)
    }

    private var normalizedValue: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(max((value - range.lowerBound) / span, 0), 1))
    }

    private func updateValue(at location: CGFloat, width: CGFloat) {
        let usableWidth = max(1, width - thumbDiameter)
        let position = min(max(location - thumbDiameter / 2, 0), usableWidth)
        let fraction = Double(position / usableWidth)
        value = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }
}

/// The visible play button.
struct TheMomentPlayButtonLabel: View {
    let fill: Color

    var body: some View {
        title
            // The highlighted fill is bright enough to wash out the title,
            // so a shadowed copy fades in behind it with the highlight.
            .background {
                title
                    .shadow(color: .black.opacity(0.45), radius: 2.5, y: 1)
                    .hoverEffect { effect, isActive, _ in
                        effect.animation(.easeInOut(duration: 0.18)) {
                            $0.opacity(isActive ? 1.0 : 0.0)
                        }
                    }
            }
            .frame(
                width: ExperienceUIStyle.primaryButtonMinimumWidth * 0.8,
                height: ExperienceUIStyle.primaryButtonHeight * 0.8
            )
            .background {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(fill)

                    Capsule(style: .continuous)
                        .fill(ExperienceUIStyle.primaryRedHighlighted)
                        .hoverEffect { effect, isActive, _ in
                            effect.animation(.easeInOut(duration: 0.18)) {
                                $0.opacity(isActive ? 1.0 : 0.0)
                            }
                        }
                }
            }
    }

    private var title: some View {
        Text(ExperienceUIStyle.theMomentPlayButtonTitle)
            .font(.system(
                size: ExperienceUIStyle.primaryButtonFontSize * 0.8,
                weight: .semibold,
                design: .default
            ))
            .foregroundStyle(ExperienceUIStyle.primaryText)
    }
}

/// Leaves the label untouched so the system gaze highlight, and the rim it
/// draws around the capsule, is not added; the label supplies its own hover
/// effects.
private struct TheMomentPlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct TheMomentView: View {

    // SwiftUI controls and the RealityKit portal are composited in separate
    // spatial layers. Empirically the native layer needs this full retreat to
    // register with the copy baked into the portal when viewed from the side.

    @Environment(AppModel.self) private var appModel
    let allowStartupPrewarm: Bool
    let portalOwnsVisuals: Bool
    let isImmersiveAttachment: Bool

    @State private var playbackStarted = false
    @State private var isPreparingYouTube = false
    @State private var showsSlowStartIndicator = false
    @State private var youtubeBlackoutTask: Task<Void, Never>?
    @State private var controlsVisible = false
    @State private var isScrubbing = false
    @State private var scrubPosition = 0.0
    @State private var resumePlaybackAfterScrubbing = false
    @State private var controlsHideTask: Task<Void, Never>?
    @State private var movieStartTransitionTask: Task<Void, Never>?
    @State private var theMomentSurfaceRevealTask: Task<Void, Never>?
    @State private var youtubePreparationTask: Task<Void, Never>?
    @State private var explanationTransitionTask: Task<Void, Never>?
    @State private var explanationRevealID = UUID()
    @State private var explanationContentOpacity = 0.0
    @State private var explanationCopyOpacity = 0.0
    @State private var explanationPlayOpacity = 0.0
    @State private var explanationPlayIsInteractive = false

    init(
        allowStartupPrewarm: Bool = false,
        portalOwnsVisuals: Bool = false,
        isImmersiveAttachment: Bool = false
    ) {
        self.allowStartupPrewarm = allowStartupPrewarm
        self.portalOwnsVisuals = portalOwnsVisuals
        self.isImmersiveAttachment = isImmersiveAttachment
    }

    private var panelContentDepthOffset: CGFloat {
        isImmersiveAttachment ? 0 : ExperienceUIStyle.portalContentDepthOffset
    }

    var body: some View {
        ZStack {
            if appModel.experienceScreen == .theMoment,
               appModel.youtubeVideoErrorCode != nil {
                ContentUnavailableView(
                    "YouTube video unavailable",
                    systemImage: "wifi.exclamationmark",
                    description: Text(
                        "Check the internet connection and make sure the video allows embedded playback."
                    )
                )
            }

            // In the immersive screen a pinch goes to the screen's own
            // manipulation, which reports short taps (`panelTapCount`), so a
            // hold, move or resize never opens the controls.
            if playbackStarted,
               !appModel.shouldShowStartScreen,
               !isImmersiveAttachment {
                Rectangle()
                    // A fully clear shape is not a reliable gaze/tap target
                    // in a plain visionOS window. Keep this effectively
                    // invisible, but renderable, just in front of the video.
                    .fill(Color.black.opacity(0.001))
                    .contentShape(Rectangle())
                    .offset(z: panelContentDepthOffset + 1)
                    .onTapGesture {
                        showControls()
                    }
                    .allowsHitTesting(
                        appModel.theMomentVideoLayerIsVisible && !controlsVisible
                    )
                    .zIndex(1)

            }

            // Keep the glass controls mounted from the initial Home screen.
            // Creating their materials at Play or on every tap can flash for
            // a frame while the visibility animation starts or ends.
            playbackControls
                .offset(z: panelContentDepthOffset + 2)
                .opacity(playbackControlsAreVisible ? 1.0 : 0.001)
                .allowsHitTesting(playbackControlsAreVisible)
                .accessibilityHidden(!playbackControlsAreVisible)
                .zIndex(2)

            startupForeground
                // The immersive attachment has no depth offset to flatten
                // for, and keeps its controls' gaze highlights unflattened.
                .compositingGroup(isEnabled: !isImmersiveAttachment)
                // Keep the start copy on the portal plane for the whole
                // transition. Changing portal ownership when playback starts
                // must not pull the button toward the viewer.
                .offset(z: isImmersiveAttachment ? 6 : panelContentDepthOffset)
                .opacity(
                    appModel.theMomentVideoLayerIsVisible
                        ? 0.0
                        : effectiveExplanationContentOpacity
                )
                .animation(
                    .easeInOut(duration: 0.8),
                    value: appModel.theMomentVideoLayerIsVisible
                )
                .allowsHitTesting(
                    !playbackStarted
                        && explanationContentOpacity > 0.99
                )
                .accessibilityHidden(
                    playbackStarted
                        || explanationContentOpacity < 0.01
                )
                .zIndex(0)
        }
        .frame(minWidth: 480, minHeight: 270)
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            AppTrace.mark("THE_MOMENT view onAppear")
            playbackStarted = false
            isPreparingYouTube = false
            controlsVisible = false
            if appModel.experienceScreen == .theMoment,
               appModel.shouldShowStartScreen {
                revealExplanationContent()
            }
        }
        .onDisappear {
            AppTrace.mark("THE_MOMENT view onDisappear")
            appModel.scrubberIsHovered = false
            appModel.scrubberIsEditing = false
            appModel.theMomentControlsAreVisible = false
            controlsHideTask?.cancel()
            movieStartTransitionTask?.cancel()
            theMomentSurfaceRevealTask?.cancel()
            youtubePreparationTask?.cancel()
            youtubeBlackoutTask?.cancel()
            explanationTransitionTask?.cancel()
            isPreparingYouTube = false
        }
        .onChange(of: appModel.experienceScreen, initial: true) { _, screen in
            if screen == .theMoment, appModel.shouldShowStartScreen {
                revealExplanationContent()
                return
            }

            if screen == .theMoment,
               !appModel.shouldShowStartScreen,
               appModel.theMomentVideoLayerIsVisible {
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    playbackStarted = true
                    controlsVisible = false
                    isPreparingYouTube = false
                }
                return
            }

            explanationTransitionTask?.cancel()
            explanationTransitionTask = nil
            explanationRevealID = UUID()
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                explanationContentOpacity = 0.0
                explanationPlayIsInteractive = false
            }
            guard screen != .theMoment else { return }
            movieStartTransitionTask?.cancel()
            movieStartTransitionTask = nil
            theMomentSurfaceRevealTask?.cancel()
            theMomentSurfaceRevealTask = nil
            youtubeBlackoutTask?.cancel()
            youtubeBlackoutTask = nil
            youtubePreparationTask?.cancel()
            youtubePreparationTask = nil
            isPreparingYouTube = false
            playbackStarted = false
            appModel.theMomentVideoLayerIsVisible = false
            controlsVisible = false
            isScrubbing = false
            resumePlaybackAfterScrubbing = false
        }
        .onChange(of: appModel.shouldShowStartScreen) { _, shouldShow in
            AppTrace.mark("THE_MOMENT shouldShowStartScreen -> \(shouldShow)")
            if shouldShow {
                movieStartTransitionTask?.cancel()
                movieStartTransitionTask = nil
                theMomentSurfaceRevealTask?.cancel()
                theMomentSurfaceRevealTask = nil
                youtubeBlackoutTask?.cancel()
                youtubeBlackoutTask = nil
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    playbackStarted = false
                    appModel.theMomentVideoLayerIsVisible = false
                    controlsVisible = false
                }
                if appModel.experienceScreen == .theMoment {
                    revealExplanationContent()
                }
            }
        }
        .onChange(of: appModel.youtubePlaybackHasStarted) { _, hasStarted in
            guard hasStarted, playbackStarted else { return }

            // The player callback owns the reveal once playback begins.
            // Leaving the timer-based reveal alive resets visible controls a
            // frame after they appear, which looks like a blink.
            theMomentSurfaceRevealTask?.cancel()
            theMomentSurfaceRevealTask = nil

            guard !appModel.theMomentVideoLayerIsVisible else {
                isPreparingYouTube = false
                return
            }

            youtubeBlackoutTask?.cancel()
            youtubeBlackoutTask = nil

            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                appModel.theMomentVideoLayerIsVisible = false
                controlsVisible = false
            }
            appModel.theMomentExplanationIsDismissing = true
            controlsHideTask?.cancel()
            controlsHideTask = nil

            youtubeBlackoutTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(550))
                guard !Task.isCancelled,
                      appModel.experienceScreen == .theMoment,
                      !appModel.shouldShowStartScreen,
                      appModel.youtubePlaybackHasStarted else { return }

                var revealTransaction = Transaction()
                revealTransaction.animation = nil
                withTransaction(revealTransaction) {
                    appModel.theMomentVideoLayerIsVisible = true
                    controlsVisible = false
                }
                appModel.markTheMomentVideoSurfaceReady()
                appModel.startTheMomentVideo()
                youtubeBlackoutTask = nil
            }

            withAnimation(.easeInOut(duration: 0.35)) {
                explanationPlayOpacity = 0.0
                explanationContentOpacity = 0.0
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard appModel.youtubePlaybackHasStarted else { return }
                isPreparingYouTube = false
            }
        }
        .onChange(of: appModel.panelTapCount) { _, _ in
            guard isImmersiveAttachment,
                  playbackStarted,
                  !appModel.shouldShowStartScreen,
                  appModel.theMomentVideoLayerIsVisible else { return }
            if !controlsVisible {
                showControls()
            }
        }
        .onChange(of: playbackControlsAreVisible) { _, visible in
            appModel.theMomentControlsAreVisible = visible
            AppTrace.mark("THE_MOMENT controls visible=\(visible)")
            if !visible && !isScrubbing {
                appModel.scrubberIsHovered = false
            }
        }
    }

    private var startupForeground: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Relive Grace's moment with the astrophage. Please take a seat before you start, statement.")
                    .font(.system(size: 25, weight: .regular, design: .default))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(9)
                    .frame(maxWidth: 560, alignment: .leading)
                    .opacity(
                        portalOwnsVisuals
                            || playbackStarted
                            || appModel.theMomentExplanationIsDismissing
                            ? 0.001
                            : effectiveExplanationCopyOpacity
                    )

                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 28) {
                            FeedbackButton(action: startPlayback) {
                                TheMomentPlayButtonLabel(fill: ExperienceUIStyle.primaryRed)
                                    .contentShape(.interaction, Capsule(style: .continuous))
                                    .contentShape(.hoverEffect, Capsule(style: .continuous))
                                    .hoverEffect { effect, isActive, _ in
                                        effect.animation(.easeInOut(duration: 0.18)) {
                                            $0.scaleEffect(isActive ? 1.1 : 1.0)
                                        }
                                    }
                                    .hoverEffectGroup()
                            }
                            .buttonStyle(TheMomentPlayButtonStyle())
                            .transaction { transaction in
                                if !explanationPlayIsInteractive {
                                    transaction.animation = nil
                                }
                            }

                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(ExperienceUIStyle.primaryText)
                                .opacity(showsSlowStartIndicator ? 1.0 : 0.0)
                                .animation(
                                    .easeInOut(duration: 0.25),
                                    value: showsSlowStartIndicator
                                )
                                .accessibilityHidden(!showsSlowStartIndicator)
                                .accessibilityLabel("Loading")
                        }

                        if let errorCode = appModel.youtubeVideoErrorCode {
                            Label(
                                errorCode == -1
                                    ? "No internet connection. Connect to the internet and try again."
                                    : errorCode == -2
                                        ? "Playback was blocked by the headset. Tap Try again."
                                        : "The YouTube video is currently unavailable.",
                                systemImage: errorCode == -1
                                    ? "wifi.slash"
                                    : errorCode == -2
                                        ? "hand.raised.slash"
                                        : "exclamationmark.circle"
                            )
                            .font(.system(size: 16, weight: .medium, design: .default))
                            .foregroundStyle(ExperienceUIStyle.primaryText.opacity(0.78))
                            .transition(.opacity)
                        }
                    }
                    .opacity(
                        playbackStarted && !isPreparingYouTube ? 0.0 : 1.0
                    )
                    .allowsHitTesting(
                        explanationPlayIsInteractive
                            && !isPreparingYouTube
                            && !playbackStarted
                    )
                    .accessibilityHidden(playbackStarted)
                }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(
                        height: appModel.youtubeVideoErrorCode == nil ? 62 : 108,
                        alignment: .topLeading
                    )
                .padding(.top, 28)
                .opacity(effectiveExplanationPlayOpacity)
                .allowsHitTesting(explanationPlayIsInteractive)
                .animation(.easeInOut(duration: 0.2), value: isPreparingYouTube)
                .task(id: isPreparingYouTube) {
                    // Only surface the spinner when starting is noticeably
                    // slow; a ready video begins without any loading UI.
                    guard isPreparingYouTube else {
                        showsSlowStartIndicator = false
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(900))
                    guard !Task.isCancelled,
                          isPreparingYouTube,
                          !playbackStarted else { return }
                    showsSlowStartIndicator = true
                }
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(.trailing, 100)
            .padding(.bottom, 100)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}

    // Opacity 0 can be culled before the text/button are rendered. Keep a
    // practically invisible layer alive during the initial warning so the
    // first visible reveal does not pay that rendering cost.
    private var shouldPrewarmStartupUI: Bool {
        allowStartupPrewarm
            && appModel.experienceScreen == .menu
            && !playbackStarted
    }

    private var effectiveExplanationContentOpacity: Double {
        shouldPrewarmStartupUI
            ? max(explanationContentOpacity, 0.001)
            : explanationContentOpacity
    }

    private var effectiveExplanationCopyOpacity: Double {
        shouldPrewarmStartupUI
            ? max(explanationCopyOpacity, 0.001)
            : explanationCopyOpacity
    }

    private var effectiveExplanationPlayOpacity: Double {
        shouldPrewarmStartupUI
            ? max(explanationPlayOpacity, 0.001)
            : explanationPlayOpacity
    }

    private var playbackControlsAreVisible: Bool {
        playbackStarted
            && !appModel.shouldShowStartScreen
            && appModel.theMomentVideoLayerIsVisible
            && controlsVisible
    }

private var playbackControls: some View {
        ZStack {
            // On the immersive screen every part of the controls can also
            // move or resize the screen; a short pinch keeps its own job.
            if isImmersiveAttachment {
                Color.black.opacity(0.18)
                    .contentShape(Rectangle())
                    .panelHandle(onTap: hideControls)
            } else {
                Color.black.opacity(0.18)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        hideControls()
                    }
            }

            VStack(spacing: 0) {
                HStack {
                    ExperienceGlassBackButton(
                        movesPanel: isImmersiveAttachment,
                        action: returnToHome
                    )

                    Spacer()

                    theMomentVolumeControl
                }

                Spacer()

                HStack(spacing: 44) {
                    playbackButton(
                        systemImage: "gobackward.10",
                        accessibilityLabel: "Skip back 10 seconds"
                    ) {
                        appModel.skipTheMoment(by: -10.0)
                        showControls()
                    }

                    playbackButton(
                        systemImage: appModel.theMomentIsPlaying ? "pause.fill" : "play.fill",
                        accessibilityLabel: appModel.theMomentIsPlaying ? "Pause" : "Play",
                        emphasized: true
                    ) {
                        appModel.toggleTheMomentPlayback()
                        showControls(autoHide: appModel.theMomentIsPlaying)
                    }

                    playbackButton(
                        systemImage: "goforward.10",
                        accessibilityLabel: "Skip forward 10 seconds"
                    ) {
                        appModel.skipTheMoment(by: 10.0)
                        showControls()
                    }
                }
                .offset(y: -1)

                Spacer()

                HStack(spacing: 14) {
                    Text(timeLabel(isScrubbing ? scrubPosition : appModel.theMomentTime))
                        .frame(width: 48, alignment: .trailing)

                    TheMomentSlider(
                        value: scrubberBinding,
                        range: 0.0...appModel.theMomentDuration,
                        onEditingChanged: scrubberEditingChanged,
                        accessibilityLabel: "The Moment scrubber",
                        accessibilityValue: { "\(Int($0)) seconds" }
                    )
                    .frame(maxWidth: .infinity)
                    .onHover { appModel.scrubberIsHovered = $0 }

                    Text(timeLabel(appModel.theMomentDuration))
                        .frame(width: 48, alignment: .leading)
                }
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(ExperienceUIStyle.primaryText.opacity(0.82))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassBackgroundEffect(in: Capsule())
            }
            .padding(28)
        }
        .environment(\.panelHandleActivity) { isActive in
            // Keep the controls up while one of them holds the screen, then
            // let them time out again as usual.
            if isActive {
                controlsHideTask?.cancel()
            } else {
                showControls()
            }
        }
    }

    private var theMomentVolumeControl: some View {
        HStack(spacing: 10) {
            Image(systemName: theMomentVolumeSystemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ExperienceUIStyle.primaryText)
                .frame(width: 22)

            TheMomentSlider(
                value: theMomentVolumeBinding,
                range: 0.0...1.0,
                onEditingChanged: volumeEditingChanged,
                accessibilityLabel: "Video volume",
                accessibilityValue: {
                    "\(Int(($0 * 100).rounded())) percent"
                }
            )
            .frame(width: 150)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .glassBackgroundEffect(in: Capsule())
    }

    private var theMomentVolumeBinding: Binding<Double> {
        Binding(
            get: { appModel.theMomentVolume },
            set: { appModel.setTheMomentVolume($0) }
        )
    }

    private var theMomentVolumeSystemImage: String {
        switch appModel.theMomentVolume {
        case ...0.001:
            return "speaker.slash.fill"
        case ..<0.34:
            return "speaker.wave.1.fill"
        case ..<0.67:
            return "speaker.wave.2.fill"
        default:
            return "speaker.wave.3.fill"
        }
    }

    private func volumeEditingChanged(_ editing: Bool) {
        controlsHideTask?.cancel()
        if !editing {
            showControls()
        }
    }

    private var scrubberBinding: Binding<Double> {
        Binding(
            get: {
                if isScrubbing {
                    return scrubPosition
                }
                return min(appModel.theMomentTime, appModel.theMomentDuration)
            },
            set: { newValue in
                scrubPosition = newValue
                appModel.previewTheMomentSeek(to: newValue)
            }
        )
    }

    private func playbackButton(
        systemImage: String,
        accessibilityLabel: String,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        PanelButton(shape: Circle(), movesPanel: isImmersiveAttachment) {
            AppTrace.mark("THE_MOMENT control tapped: \(accessibilityLabel)")
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: emphasized ? 30 : 26, weight: .semibold))
                .frame(width: emphasized ? 68 : 56, height: emphasized ? 68 : 56)
                .foregroundStyle(ExperienceUIStyle.primaryText)
                .glassBackgroundEffect(in: Circle())
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private func scrubberEditingChanged(_ editing: Bool) {
        appModel.scrubberIsEditing = editing
        controlsHideTask?.cancel()

        if editing {
            AppTrace.mark("THE_MOMENT scrub begin")
            resumePlaybackAfterScrubbing = appModel.theMomentIsPlaying
            appModel.pauseTheMomentForScrubbing()
            isScrubbing = true
            scrubPosition = min(appModel.theMomentTime, appModel.theMomentDuration)
            return
        }

        AppTrace.mark("THE_MOMENT scrub end position=\(scrubPosition)")
        appModel.finishTheMomentScrubbing(
            to: scrubPosition,
            resumePlayback: resumePlaybackAfterScrubbing
        )
        isScrubbing = false
        let shouldResume = resumePlaybackAfterScrubbing
        resumePlaybackAfterScrubbing = false
        showControls(autoHide: shouldResume)
    }

    private func showControls(autoHide: Bool? = nil) {
        controlsHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible = true
        }

        let shouldAutoHide = autoHide ?? appModel.theMomentIsPlaying
        guard shouldAutoHide, !isScrubbing else { return }

        controlsHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                controlsVisible = false
            }
        }
    }

    private func hideControls() {
        controlsHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible = false
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func startPlayback() {
        AppTrace.mark("THE_MOMENT Play button tapped")
        guard !playbackStarted,
              !isPreparingYouTube,
              appModel.shouldShowStartScreen else {
            AppTrace.mark(
                "THE_MOMENT Play ignored playing=\(playbackStarted) preparing=\(isPreparingYouTube) home=\(appModel.shouldShowStartScreen)"
            )
            return
        }

        var immediateTransaction = Transaction()
        immediateTransaction.animation = nil
        withTransaction(immediateTransaction) {
            isPreparingYouTube = true
            explanationPlayIsInteractive = false
        }
        if appModel.youtubeVideoIsReady,
           appModel.youtubeVideoErrorCode == nil {
            beginPlaybackTransition(userInitiated: true)
            return
        }

        let shouldReloadSurface = appModel.youtubeVideoErrorCode != nil
        youtubePreparationTask?.cancel()
        youtubePreparationTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled,
                  appModel.experienceScreen == .theMoment,
                  appModel.shouldShowStartScreen else { return }

            appModel.beginYouTubePreparation()

            if shouldReloadSurface {
                appModel.youtubeSurfaceReloadID = UUID()
            }
            AppTrace.mark("YOUTUBE permanent surface requested by Play")

            let ready = await waitUntilYouTubeIsReady()
            guard !Task.isCancelled,
                  appModel.experienceScreen == .theMoment,
                  appModel.shouldShowStartScreen else { return }

            guard ready else {
                isPreparingYouTube = false
                AppTrace.mark("YOUTUBE preparation did not complete")
                return
            }
            beginPlaybackTransition()
        }
    }

    private func beginPlaybackTransition(userInitiated: Bool = false) {
        guard appModel.youtubeVideoIsReady,
              appModel.youtubeVideoErrorCode == nil,
              !playbackStarted,
              appModel.shouldShowStartScreen else { return }
        AppTrace.mark("THE_MOMENT YouTube ready; movie transition begin")
        var immediateTransaction = Transaction()
        immediateTransaction.animation = nil
        withTransaction(immediateTransaction) {
            isPreparingYouTube = true
            explanationPlayIsInteractive = false
        }
        explanationTransitionTask?.cancel()
        explanationTransitionTask = nil
        playbackStarted = true
        controlsVisible = false
        movieStartTransitionTask?.cancel()
        movieStartTransitionTask = nil

        appModel.theMomentExplanationIsDismissing = true
        appModel.theMomentVideoLayerIsVisible = false
        withAnimation(.easeInOut(duration: 0.55)) {
            explanationContentOpacity = 0.0
            explanationPlayOpacity = 0.0
        }
        AppTrace.mark("THE_MOMENT loading state active; explanation remains visible")
        appModel.startTheMomentPlayback(startImmediately: userInitiated)

        theMomentSurfaceRevealTask?.cancel()
        theMomentSurfaceRevealTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled,
                  playbackStarted,
                  appModel.experienceScreen == .theMoment,
                  !appModel.shouldShowStartScreen,
                  !appModel.theMomentVideoLayerIsVisible else { return }

            var revealTransaction = Transaction()
            revealTransaction.animation = nil
            withTransaction(revealTransaction) {
                appModel.theMomentVideoLayerIsVisible = true
                controlsVisible = false
                isPreparingYouTube = false
            }
            appModel.markTheMomentVideoSurfaceReady()
            appModel.startTheMomentVideo()
            theMomentSurfaceRevealTask = nil
        }
    }

    private func revealExplanationContent() {
        explanationTransitionTask?.cancel()
        let revealID = UUID()
        explanationRevealID = revealID
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            playbackStarted = false
            appModel.theMomentVideoLayerIsVisible = false
            isPreparingYouTube = false
            controlsVisible = false
            isScrubbing = false
            resumePlaybackAfterScrubbing = false
                explanationContentOpacity = 1.0
                explanationCopyOpacity = 0.0
                explanationPlayOpacity = 0.0
                explanationPlayIsInteractive = false
            }

        explanationTransitionTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled,
                  explanationRevealID == revealID,
                  appModel.experienceScreen == .theMoment,
                  appModel.shouldShowStartScreen,
                  !playbackStarted else { return }

            AppTrace.mark("THE_MOMENT explanation content fade in")
            let revealDuration = appModel.initialHomeSceneRevealIsAllowed
                ? AppModel.homeReturnRevealDuration
                : AppModel.initialHomeRevealDuration
            withAnimation(.easeInOut(duration: revealDuration)) {
                explanationCopyOpacity = 1.0
                explanationPlayOpacity = 1.0
                appModel.revealEmitterWithHomeContentIfNeeded()
            }
            try? await Task.sleep(for: .seconds(revealDuration))
            guard explanationRevealIsCurrent(revealID) else { return }
            explanationPlayIsInteractive = true
            AppTrace.mark("THE_MOMENT Play button enabled")
        }

    }

    private func explanationRevealIsCurrent(_ revealID: UUID) -> Bool {
        !Task.isCancelled
            && explanationRevealID == revealID
            && appModel.experienceScreen == .theMoment
            && appModel.shouldShowStartScreen
            && !playbackStarted
    }

    private func returnToHome() {
            AppTrace.mark("THE_MOMENT close button tapped")
        controlsHideTask?.cancel()
        movieStartTransitionTask?.cancel()
        youtubePreparationTask?.cancel()
        youtubePreparationTask = nil
        isPreparingYouTube = false
        movieStartTransitionTask = nil
        controlsVisible = false

        if appModel.shouldShowStartScreen, !playbackStarted {
            explanationTransitionTask?.cancel()
            AppTrace.mark("THE_MOMENT explanation content fade out")
            withAnimation(.easeInOut(duration: 0.5)) {
                explanationContentOpacity = 0.0
            }
            explanationTransitionTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled,
                      (appModel.mainWindowIsOpen || appModel.immersivePanelIsVisible),
                      appModel.experienceScreen == .theMoment,
                      appModel.shouldShowStartScreen else { return }
                appModel.returnToModeMenu()
            }
        } else {
            appModel.returnToModeMenu()
        }
    }

    private func waitUntilYouTubeIsReady() async -> Bool {
        for _ in 0..<300 {
            guard !Task.isCancelled else { return false }
            if appModel.youtubeVideoIsReady {
                AppTrace.mark("YOUTUBE ready after Play")
                return true
            }
            if appModel.youtubeVideoErrorCode != nil { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }

        guard !Task.isCancelled,
              !appModel.youtubeVideoIsReady else {
            return appModel.youtubeVideoIsReady
        }
        appModel.youtubePlayerDidFail(errorCode: -1)
        return false
    }
}

final class YouTubeContainerView: UIView {
    let webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)

        isOpaque = false
        backgroundColor = .clear
        // The player is driven only through JavaScript commands. UIKit hit
        // testing runs before SwiftUI's, so an interactive web view here
        // swallows the pinch meant for the Home button while SwiftUI hover
        // still highlights it.
        isUserInteractionEnabled = false
        webView.isUserInteractionEnabled = false
        refreshPanelClipping()

        webView.frame = bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshPanelClipping()
        webView.frame = bounds
    }

    func refreshPanelClipping() {
        clipsToBounds = true
        layer.masksToBounds = true
        layer.cornerRadius = ExperienceUIStyle.panelCornerRadius
        layer.cornerCurve = .continuous
    }
}

struct YouTubeVideoSurface: UIViewRepresentable {
    private static let embedOrigin = "https://project-hail-mary.example"
    let videoID: String
    let appModel: AppModel

    func makeCoordinator() -> Coordinator {
        Coordinator(appModel: appModel)
    }

    func makeUIView(context: Context) -> YouTubeContainerView {
        AppTrace.mark("YOUTUBE surface makeUIView")
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(
            context.coordinator,
            name: Coordinator.messageName
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: playerScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        let container = YouTubeContainerView(webView: webView)

        appModel.attachYouTubeCommandHandler(id: context.coordinator.id) { [weak webView] command in
            guard let webView else { return }
            let javascript: String
            switch command {
            case .startFromBeginning:
                javascript = "window.phmStartFromBeginning && window.phmStartFromBeginning();"
            case .play:
                javascript = "window.phmPlay && window.phmPlay();"
            case .mute:
                javascript = "window.phmMute && window.phmMute();"
            case .pause:
                javascript = "window.phmPause && window.phmPause();"
            case let .fadeOutAndPause(milliseconds):
                javascript = "window.phmFadeOutAndPause && window.phmFadeOutAndPause(\(milliseconds));"
            case let .seek(seconds, allowSeekAhead):
                javascript = "window.phmSeek && window.phmSeek(\(seconds), \(allowSeekAhead));"
            case let .setVolume(volume):
                javascript = "window.phmSetVolume && window.phmSetVolume(\(volume * 100.0));"
            case .reset:
                javascript = "window.phmReset && window.phmReset();"
            }
            webView.evaluateJavaScript(javascript) { _, error in
                if let error {
                    AppTrace.mark("YOUTUBE command failed: \(error.localizedDescription)")
                }
            }
        }

        guard let url = embedURL(videoID: videoID) else {
            appModel.youtubePlayerDidFail(errorCode: -1)
            return container
        }
        var request = URLRequest(url: url)
        request.setValue(Self.embedOrigin + "/", forHTTPHeaderField: "Referer")
        webView.load(request)
        return container
    }

    func updateUIView(_ container: YouTubeContainerView, context: Context) {
        container.refreshPanelClipping()
    }

    static func dismantleUIView(
        _ container: YouTubeContainerView,
        coordinator: Coordinator
    ) {
        AppTrace.mark("YOUTUBE surface dismantleUIView")
        coordinator.appModel.detachYouTubeCommandHandler(id: coordinator.id)
        let webView = container.webView
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.messageName
        )
        webView.stopLoading()
        coordinator.webView = nil
    }

    private func embedURL(videoID: String) -> URL? {
        var components = URLComponents(
            string: "https://www.youtube.com/embed/\(videoID)"
        )
        components?.queryItems = [
            URLQueryItem(name: "enablejsapi", value: "1"),
            URLQueryItem(name: "autoplay", value: "0"),
            URLQueryItem(name: "controls", value: "0"),
            URLQueryItem(name: "cc_load_policy", value: "0"),
            URLQueryItem(name: "disablekb", value: "1"),
            URLQueryItem(name: "fs", value: "0"),
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "origin", value: Self.embedOrigin),
            URLQueryItem(name: "widget_referrer", value: Self.embedOrigin)
        ]
        return components?.url
    }

    private var playerScript: String {
        """
        (function() {
          var statusTimer = null;
          var bindTimer = null;
          var readySent = false;
          var playAttemptID = 0;
          var startRequestID = 0;
          var fadeOutID = 0;
          var restoreAudioWhenPlaying = false;
          var audioRestoreTimer = null;
          var preloadMuted = true;
          var playbackAuthorized = false;
          var unsolicitedStopAt = 0;
          var desiredVolume = \(min(max(appModel.theMomentVolume, 0.0), 1.0) * 100.0);

          function post(payload) {
            try {
              window.webkit.messageHandlers.phmYouTube.postMessage(payload);
            } catch (_) {}
          }

          function numberOrZero(value) {
            return typeof value === 'number' && isFinite(value) ? value : 0;
          }

          function hideYouTubeChrome() {
            if (document.getElementById('phmYouTubeChromeStyle')) return;
            var style = document.createElement('style');
            style.id = 'phmYouTubeChromeStyle';
            style.textContent = `
              .ytp-chrome-controls,
              .ytp-chrome-bottom,
              .ytp-gradient-top,
              .ytp-gradient-bottom,
              .ytp-large-play-button,
              .ytp-bezel,
              .ytp-pause-overlay,
              .ytp-cued-thumbnail-overlay,
              .ytp-watermark,
              .ytp-title,
              .ytp-show-cards-title,
              .ytp-ce-element,
              .ytp-caption-window-container,
              .caption-window,
              .captions-text {
                display: none !important;
                visibility: hidden !important;
                opacity: 0 !important;
              }
            `;
            (document.head || document.documentElement).appendChild(style);
          }

          hideYouTubeChrome();

          function youtubePlayer() {
            var player = null;
            try {
              if (window.YT && typeof window.YT.get === 'function') {
                player = window.YT.get('movie_player');
              }
            } catch (_) {}
            if (!player) player = document.getElementById('movie_player');
            if (!player
                || typeof player.playVideo !== 'function'
                || typeof player.getPlayerState !== 'function') {
              return null;
            }
            return player;
          }

          function disableCaptions(player) {
            if (!player) return;
            try { player.setOption('captions', 'track', {}); } catch (_) {}
            try { player.setOption('cc', 'track', {}); } catch (_) {}
            try { player.unloadModule('captions'); } catch (_) {}
            try { player.unloadModule('cc'); } catch (_) {}
          }

          function muteForPreload(player) {
            if (!player) return;
            preloadMuted = true;
            restoreAudioWhenPlaying = false;
            try {
              // YouTube can still begin playback while the embed is being
              // prepared, even with autoplay=0. Keep the preloaded player
              // paused at the beginning until the user taps the button.
              player.pauseVideo();
              player.mute();
              player.setVolume(0);
            } catch (_) {}
          }

          function emitStatus() {
            var player = youtubePlayer();
            if (!player) return;
            var state = Number(player.getPlayerState());

            if (!playbackAuthorized) {
              if (state === 1 || state === 3) {
                // The player keeps reporting playing/buffering for a while
                // after pauseVideo(). Retry at most twice a second and trace
                // once per unsolicited start, not on every status tick.
                var now = Date.now();
                if (!unsolicitedStopAt || now - unsolicitedStopAt >= 500) {
                  if (!unsolicitedStopAt) {
                    post({ type: 'trace', message: 'unsolicited preload playback stopped state=' + state });
                  }
                  unsolicitedStopAt = now;
                  try {
                    player.pauseVideo();
                    player.mute();
                    player.setVolume(0);
                  } catch (_) {}
                }
              } else {
                unsolicitedStopAt = 0;
              }
              post({
                type: 'status',
                time: 0,
                duration: numberOrZero(player.getDuration()),
                state: 2
              });
              return;
            }
            unsolicitedStopAt = 0;

            if (state === 1 && restoreAudioWhenPlaying && !audioRestoreTimer) {
              audioRestoreTimer = setTimeout(function() {
                audioRestoreTimer = null;
                var currentPlayer = youtubePlayer();
                if (!currentPlayer
                    || Number(currentPlayer.getPlayerState()) !== 1
                    || !restoreAudioWhenPlaying) return;
                restoreAudioWhenPlaying = false;
                try {
                  currentPlayer.setVolume(desiredVolume);
                  if (desiredVolume > 0) {
                    currentPlayer.unMute();
                  } else {
                    currentPlayer.mute();
                  }
                } catch (_) {}
                post({ type: 'trace', message: 'audio restored after visible playback' });
              }, 300);
            } else if (state !== 1 && audioRestoreTimer) {
              clearTimeout(audioRestoreTimer);
              audioRestoreTimer = null;
            }

            post({
              type: 'status',
              time: numberOrZero(player.getCurrentTime()),
              duration: numberOrZero(player.getDuration()),
              state: isFinite(state) ? state : -1
            });
          }

          function bindPlayer() {
            var player = youtubePlayer();
            if (!player) return false;

            if (!readySent) {
              readySent = true;
              disableCaptions(player);
              post({ type: 'trace', message: 'player API ready' });
              post({
                type: 'ready',
                duration: numberOrZero(player.getDuration())
              });
            }
            if (preloadMuted) muteForPreload(player);
            if (!statusTimer) {
              emitStatus();
              statusTimer = setInterval(emitStatus, 100);
            }
            return true;
          }

          window.phmPlay = function() {
            if (!playbackAuthorized) {
              post({ type: 'trace', message: 'play ignored without user start' });
              return;
            }
            var player = youtubePlayer();
            if (!player) {
              setTimeout(window.phmPlay, 100);
              return;
            }
            var attemptID = ++playAttemptID;
            if (audioRestoreTimer) {
              clearTimeout(audioRestoreTimer);
              audioRestoreTimer = null;
            }
            restoreAudioWhenPlaying = true;
            preloadMuted = false;
            disableCaptions(player);
            post({
              type: 'trace',
              message: 'playVideo requested state=' + Number(player.getPlayerState())
            });
            try {
              player.mute();
              player.setVolume(desiredVolume);
              player.playVideo();
            } catch (_) {}
            setTimeout(function() { disableCaptions(player); }, 500);
            setTimeout(function() { disableCaptions(player); }, 1500);

            setTimeout(function() {
              if (attemptID !== playAttemptID) return;
              var state = Number(player.getPlayerState());
              if (state === 1 || state === 3) return;
              post({
                type: 'trace',
                message: 'muted play retrying state=' + state
              });
              try {
                player.mute();
                player.playVideo();
              } catch (_) {}

              setTimeout(function() {
                if (attemptID !== playAttemptID) return;
                var retryState = Number(player.getPlayerState());
                if (retryState !== 1 && retryState !== 3) {
                  post({
                    type: 'trace',
                    message: 'muted play rejected state=' + retryState
                  });
                  restoreAudioWhenPlaying = false;
                  post({ type: 'autoplayBlocked', code: -2 });
                }
              }, 900);
            }, 700);
            emitStatus();
          };

          window.phmStartFromBeginning = function() {
            var requestID = ++startRequestID;
            function startWhenReady() {
              if (requestID !== startRequestID) return;
              var player = youtubePlayer();
              if (!player) {
                setTimeout(startWhenReady, 100);
                return;
              }
              try {
                player.pauseVideo();
                player.seekTo(0, true);
              } catch (_) {}
              var resetDeadline = Date.now() + 2000;
              function playAtZero() {
                if (requestID !== startRequestID) return;
                var currentTime = numberOrZero(player.getCurrentTime());
                if (currentTime > 0.15 && Date.now() < resetDeadline) {
                  setTimeout(playAtZero, 50);
                  return;
                }
                if (currentTime > 0.15) {
                  try { player.seekTo(0, true); } catch (_) {}
                }
                playbackAuthorized = true;
                preloadMuted = false;
                post({ type: 'trace', message: 'explicit start seeked to zero' });
                window.phmPlay();
              }
              playAtZero();
            }
            startWhenReady();
          };

          window.phmPause = function() {
            playAttemptID += 1;
            fadeOutID += 1;
            if (audioRestoreTimer) {
              clearTimeout(audioRestoreTimer);
              audioRestoreTimer = null;
            }
            restoreAudioWhenPlaying = false;
            var player = youtubePlayer();
            if (player) player.pauseVideo();
            emitStatus();
          };

          window.phmMute = function() {
            playAttemptID += 1;
            startRequestID += 1;
            preloadMuted = true;
            playbackAuthorized = false;
            if (audioRestoreTimer) {
              clearTimeout(audioRestoreTimer);
              audioRestoreTimer = null;
            }
            var player = youtubePlayer();
            if (player) muteForPreload(player);
          };

          window.phmFadeOutAndPause = function(milliseconds) {
            playAttemptID += 1;
            var currentFadeID = ++fadeOutID;
            if (audioRestoreTimer) {
              clearTimeout(audioRestoreTimer);
              audioRestoreTimer = null;
            }
            restoreAudioWhenPlaying = false;
            var player = youtubePlayer();
            if (!player) return;

            var restoreVolume = desiredVolume;
            var startVolume = restoreVolume;
            try {
              var playerVolume = Number(player.getVolume());
              if (isFinite(playerVolume)) startVolume = Math.max(0, Math.min(100, playerVolume));
            } catch (_) {}

            var stepCount = 9;
            var stepDuration = Math.max(25, Number(milliseconds) || 450) / stepCount;
            function fadeStep(step) {
              if (currentFadeID !== fadeOutID) return;
              var progress = Math.min(1, step / stepCount);
              try {
                player.setVolume(Math.max(0, startVolume * (1 - progress)));
              } catch (_) {}

              if (progress >= 1) {
                try {
                  player.pauseVideo();
                  player.mute();
                  desiredVolume = restoreVolume;
                  player.setVolume(restoreVolume);
                } catch (_) {}
                emitStatus();
                post({ type: 'trace', message: 'audio fade completed; video paused at limit' });
                return;
              }
              setTimeout(function() { fadeStep(step + 1); }, stepDuration);
            }
            fadeStep(0);
          };

          window.phmSeek = function(seconds) {
            var player = youtubePlayer();
            if (!player) return;
            player.seekTo(Math.max(0, Number(seconds) || 0), true);
            emitStatus();
          };

          window.phmSetVolume = function(volume) {
            desiredVolume = Math.max(0, Math.min(100, Number(volume) || 0));
            var player = youtubePlayer();
            if (!player) return;
            try {
              player.setVolume(desiredVolume);
              if (desiredVolume > 0) {
                player.unMute();
              } else {
                player.mute();
              }
            } catch (_) {}
          };

          window.phmReset = function() {
            playAttemptID += 1;
            startRequestID += 1;
            fadeOutID += 1;
            preloadMuted = true;
            playbackAuthorized = false;
            if (audioRestoreTimer) {
              clearTimeout(audioRestoreTimer);
              audioRestoreTimer = null;
            }
            restoreAudioWhenPlaying = false;
            var player = youtubePlayer();
            if (!player) return;
            player.pauseVideo();
            player.seekTo(0, true);
            player.mute();
            player.setVolume(0);
            emitStatus();
          };

          if (!bindPlayer()) {
            bindTimer = setInterval(function() {
              if (!bindPlayer()) return;
              clearInterval(bindTimer);
              bindTimer = null;
            }, 250);
          }
        })();
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let messageName = "phmYouTube"
        let id = UUID()
        let appModel: AppModel
        weak var webView: WKWebView?

        init(appModel: AppModel) {
            self.appModel = appModel
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == Self.messageName,
                  let payload = message.body as? [String: Any],
                  let type = payload["type"] as? String else { return }

            switch type {
            case "ready":
                let duration = (payload["duration"] as? NSNumber)?.doubleValue ?? 0.0
                appModel.youtubePlayerDidBecomeReady(duration: duration)

            case "status":
                let time = (payload["time"] as? NSNumber)?.doubleValue ?? 0.0
                let duration = (payload["duration"] as? NSNumber)?.doubleValue ?? 0.0
                let state = (payload["state"] as? NSNumber)?.intValue ?? -1
                appModel.youtubePlayerDidUpdate(
                    time: time,
                    duration: duration,
                    state: state
                )

            case "error":
                let code = (payload["code"] as? NSNumber)?.intValue ?? -1
                appModel.youtubePlayerDidFail(errorCode: code)

            case "autoplayBlocked":
                AppTrace.mark("YOUTUBE autoplay blocked by WebKit/YouTube")
                appModel.youtubePlayerDidFail(errorCode: -2)

            case "trace":
                let detail = payload["message"] as? String ?? "unknown"
                AppTrace.mark("YOUTUBE JS \(detail)")

            default:
                break
            }
        }
    }
}

#Preview {
    TheMomentView()
        .environment(AppModel())
}
