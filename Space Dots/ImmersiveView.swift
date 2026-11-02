import ARKit
import Foundation
import RealityKit
import SwiftUI
import UIKit

@MainActor
private final class ImmersiveSceneState {
    var panelGrip: Entity?
    var panelGrabSurfaces: [Entity] = []
    /// Covers the start button's gap; grabbable only while the movie plays.
    var panelPlaybackGrabSurface: Entity?
    /// The pinch on the screen in progress, to tell a tap from a hold, move
    /// or resize.
    var panelPress: PanelPress?
    /// The drag of the screen around the viewer in progress.
    var panelDrag: PanelDrag?
    /// The tracked pinch position during a drag, when the input has one.
    var panelHandPosition: SIMD3<Float>?
    /// True while a SwiftUI control on the screen, rather than a grab
    /// surface, is moving or resizing it.
    var panelHandleIsActive = false
    var panelHandleGripStartPosition = SIMD3<Float>.zero
    var panelHandleGripStartScale: Float = 1
    // Head AnchorEntity transforms are hidden from the app, so reading one
    // always returns the start pose. World tracking reports the real device
    // pose, which places the screen level in front of the viewer and lets
    // it turn toward where the viewer is now.
    let worldTrackingSession = ARKitSession()
    let worldTracking = WorldTrackingProvider()
    /// The screen lives in world space. It stays hidden until it has been
    /// placed level in front of the viewer.
    var panelIsPlaced = false
    /// Where the visible screen is heading, in world space.
    var panelTargetPosition = SIMD3<Float>(0, 1.4, -1.25)
    /// The last known head position, for frames without a tracked pose.
    var lastViewerPosition = SIMD3<Float>(0, 1.4, 0)
    var worldTrackingIsStarted = false

    func startWorldTracking() {
        guard !worldTrackingIsStarted else { return }
        worldTrackingIsStarted = true
        guard WorldTrackingProvider.isSupported else {
            AppTrace.mark("IMMERSIVE world tracking unsupported")
            return
        }
        Task { @MainActor in
            do {
                try await worldTrackingSession.run([worldTracking])
            } catch {
                AppTrace.mark("IMMERSIVE world tracking failed: \(error)")
            }
        }
    }

    func currentDeviceTransform() -> simd_float4x4? {
        guard worldTracking.state == .running,
              let device = worldTracking.queryDeviceAnchor(
                  atTimestamp: CACurrentMediaTime()
              ),
              device.isTracked else { return nil }
        return device.originFromAnchorTransform
    }

    /// The viewer's head position in world space, remembered for frames
    /// where tracking has no pose.
    func viewerPosition() -> SIMD3<Float> {
        if let device = currentDeviceTransform() {
            let position = device.columns.3
            lastViewerPosition = SIMD3<Float>(position.x, position.y, position.z)
        }
        return lastViewerPosition
    }

    /// Places the screen level in the viewer's current direction. If no head
    /// pose arrives, use the launch window or the space's forward direction.
    @discardableResult
    func placePanelIfNeeded(
        panelEntity: Entity,
        panelGrip: Entity,
        restOffset: SIMD3<Float>,
        windowPosition: SIMD3<Float>?,
        useFallback: Bool = false
    ) -> Bool {
        guard !panelIsPlaced else { return true }
        var viewer = lastViewerPosition
        var forward = SIMD3<Float>(0, 0, -1)
        let device = currentDeviceTransform()
        if let device {
            let position = device.columns.3
            viewer = SIMD3<Float>(position.x, position.y, position.z)
            lastViewerPosition = viewer
        }
        var towardWindow: SIMD2<Float>?
        if let windowPosition {
            let offset = SIMD2<Float>(
                windowPosition.x - viewer.x,
                windowPosition.z - viewer.z
            )
            // Anything else is not a window standing in front of the viewer.
            if (0.3...10).contains(simd_length(offset)) {
                towardWindow = simd_normalize(offset)
            }
        }
        if let device {
            let lookDirection = -device.columns.2
            var horizontal = SIMD2<Float>(lookDirection.x, lookDirection.z)
            if simd_length(horizontal) < 0.2 {
                // Looking almost straight up or down: the head's up axis
                // still points where the face is turned.
                let up = device.columns.1
                horizontal = SIMD2<Float>(up.x, up.z) * (lookDirection.y < 0 ? 1 : -1)
            }
            if simd_length(horizontal) > 0.001 {
                horizontal = simd_normalize(horizontal)
                forward = SIMD3<Float>(horizontal.x, 0, horizontal.y)
            } else if let towardWindow {
                forward = SIMD3<Float>(towardWindow.x, 0, towardWindow.y)
            }
        } else if !useFallback {
            return false
        } else if let towardWindow {
            forward = SIMD3<Float>(towardWindow.x, 0, towardWindow.y)
        }
        let right = SIMD3<Float>(-forward.z, 0, forward.x)
        let position = viewer
            + right * restOffset.x
            + SIMD3<Float>(0, restOffset.y, 0)
            + forward * -restOffset.z
        let orientation = Self.facing(from: position, toward: viewer)
        panelEntity.position = position
        panelEntity.orientation = orientation
        panelGrip.position = position
        panelGrip.orientation = orientation
        panelTargetPosition = position
        panelIsPlaced = true
        AppTrace.mark(
            "IMMERSIVE panel placed level "
                + (device != nil
                    ? "where the head is turned"
                    : towardWindow != nil ? "toward launch window (no tracked pose)" : "(no tracked pose)")
        )
        return true
    }

    /// A yaw-only orientation whose +Z (the screen's front) points at
    /// `viewer` along the floor, so the screen never pitches or rolls.
    static func facing(
        from position: SIMD3<Float>,
        toward viewer: SIMD3<Float>
    ) -> simd_quatf {
        let toViewer = SIMD2<Float>(viewer.x - position.x, viewer.z - position.z)
        guard simd_length(toViewer) > 0.001 else { return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) }
        return simd_quatf(angle: atan2(toViewer.x, toViewer.y), axis: [0, 1, 0])
    }
    var panelEntity: Entity?
    var panelPortal: ParallaxRibbonScene?
    var panelVisual: Entity?
    var panelVisualIsHiddenFromBehind = false
    var panelFadeInScheduled = false
    /// Starts only after the panel has its final bounds and is placed.
    var startupIntroElapsed: Float?
    /// Set once the fade-in is complete, so heavy loading cannot make it
    /// stutter.
    var panelFadeIsComplete = false
    var assetLoadTask: Task<Void, Never>?
    /// Gates everything that drives the orbiting models, the Petrova
    /// Indicator and the particles until their models are loaded.
    var spatialAssetsAreLoaded = false
    var orbitingModels: OrbitingSpaceModels?
    var activationBox: ActivationBox?
    var physicsRoot: Entity?
    var particles: AstrophageParticles?
}

private struct PanelPress {
    let startTime: TimeInterval
    let startPosition: SIMD3<Float>
    let startScale: Float
    var changedPanel = false
}

/// Moves the screen around the viewer like a window: turning with the
/// pinching hand carries it all the way around, pushing or pulling the hand
/// sends it away or brings it closer, and raising or lowering the hand
/// lifts or drops it. The hand position is estimated from the grip's travel.
private struct PanelDrag {
    /// Grip position last frame, to take this frame's hand travel.
    var lastGripPosition: SIMD3<Float>
    var hand: SIMD3<Float>
    /// Whether `hand` is the tracked pinch rather than an estimate.
    var handIsMeasured = false
    var lastHandAzimuth: Float?
    /// Around the viewer, in radians; unwrapped so it can pass ±180°.
    var azimuth: Float
    /// Along the floor, from the viewer.
    var distance: Float
    /// World height of the screen's center.
    var height: Float
    /// The grip's and the screen's scale when the drag began; the screen
    /// grows by a power of the grip's change.
    let startGripScale: Float
    let startScale: Float

    func targetPosition(around viewer: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(
            viewer.x + sin(azimuth) * distance,
            height,
            viewer.z + cos(azimuth) * distance
        )
    }
}

@MainActor
private struct RetiringAstrophageGeneration {
    let particles: AstrophageParticles
    let origin: Entity
    let rig: Entity
    var elapsed: Float = 0.0
}

struct ImmersiveView: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var sceneState = ImmersiveSceneState()

    private static let panelAttachmentID = "experience-panel"
    /// Where the screen first appears, relative to a level view straight
    /// ahead: 1.25 m away, slightly below eye height.
    private static let panelRestPosition = SIMD3<Float>(0, -0.07, -1.25)
    /// The warning panel's entrance: black panel and copy fade in together.
    private static let panelFadeInDuration: Float = 2.6
    // The panel rests 1.25 m from the viewer, so this leaves the centred
    // logo 0.75 m away at the start of its entrance.
    private static let logoEntranceDistance: Float = 0.4
    /// How long the screen waits for a tracked head pose before it is
    /// placed in front of the space's origin instead.
    private static let panelPlacementTimeout: Duration = .seconds(2)
    /// How long it waits for the launch window's position before it goes
    /// where the head is turned instead.
    private static let panelWindowPositionTimeout: Duration = .milliseconds(700)
    // Dragging the screen. Hand reach is the assumed distance from the
    // body's axis to the pinching hand; turning the hand about the viewer
    // turns the screen by the same angle. Pushing or pulling the hand moves
    // the screen in proportion to how far away it is: at the start distance
    // about 4 times the hand's travel, far off much more, so a push or two
    // sends it from arm's length to cinema distance. Raising the hand lifts
    // the screen by the same angle it is seen under.
    private static let panelHandReach: Float = 0.4
    /// Relative distance change per meter of hand travel.
    private static let panelDepthGain: Float = 3.2
    private static let panelDistanceRange: ClosedRange<Float> = 0.6...25
    // Resizing with two hands: spreading them twice as wide makes the
    // screen `2^panelScaleExponent` as big. At the largest scale it is about
    // 25 m wide, an IMAX-sized screen when set far enough away.
    private static let panelScaleRange: ClosedRange<Float> = 0.85...27
    private static let panelScaleExponent: Float = 1.6
    /// Highest and lowest the screen goes, as a slope from eye height.
    private static let panelMaximumElevationSlope: Float = 1
    /// A larger jump in one frame is a lost or swapped hand pose, not a move.
    private static let panelMaximumHandStep: Float = 0.25
    // The Astrophage flow and its red oval come from behind the screen:
    // their rig stands at the viewer and turns toward the screen, so moving
    // the screen to the right makes the flow come from the right. Emitted
    // particles keep flying, so the stream swings over gradually.
    private static let astrophageOriginOffset = SIMD3<Float>(0, 0.5, -2.5)
    private static let astrophageTurnRate: Float = 1.5
    /// How far behind the screen the oval hangs once the screen is farther
    /// away than the oval's usual place.
    private static let astrophageOvalGapBehindScreen: Float = 1.5
    /// The screen's size over its distance as it first appears. The oval
    /// is sized to stick out around a screen that looks this big; a screen
    /// that looks bigger makes the oval grow along with it.
    private static let astrophageOvalReferencePanelSize: Float = 1.5 / 1.25
    private static let astrophageOvalMaximumGrowth: Float = 20

    /// A new Astrophage rig at the viewer, turned straight at the screen.
    private static func makeAstrophageRig(
        viewer: SIMD3<Float>,
        panel: SIMD3<Float>
    ) -> Entity {
        let rig = Entity()
        rig.name = "Astrophage Screen Direction Rig"
        rig.position = viewer
        rig.orientation = ImmersiveSceneState.facing(from: panel, toward: viewer)
        return rig
    }

    /// Turns the active rig toward where the screen is now and keeps the
    /// oval behind it.
    private static func followPanel(
        rig: Entity,
        particles: AstrophageParticles,
        panel: SIMD3<Float>,
        panelScale: Float,
        deltaTime: Float
    ) {
        let target = ImmersiveSceneState.facing(from: panel, toward: rig.position)
        let turnSmoothing = 1 - exp(-deltaTime * astrophageTurnRate)
        rig.orientation = simd_slerp(rig.orientation, target, turnSmoothing)
        let panelDistance = simd_length(SIMD2<Float>(
            panel.x - rig.position.x,
            panel.z - rig.position.z
        ))
        let apparentPanelSize = panelScale / max(panelDistance, 0.001)
        let growth = min(
            max(apparentPanelSize / astrophageOvalReferencePanelSize, 1),
            astrophageOvalMaximumGrowth
        )
        // The oval hangs straight behind the screen as seen from the
        // viewer, so it follows the screen at once, sideways and up or down.
        let toPanel = panel - rig.position
        let panelRange = simd_length(toPanel)
        guard panelRange > 0.001 else { return }
        let ovalDistance = particles.ovalViewerDistance(
            for: panelRange + astrophageOvalGapBehindScreen
        )
        particles.placeOval(
            at: rig.position + (toPanel / panelRange) * ovalDistance,
            relativeTo: rig.parent,
            viewerDistance: ovalDistance,
            growth: growth
        )
    }
    // A pinch on the screen counts as a tap (showing the video controls)
    // only when it is short and leaves the screen where and as big as it
    // was. Anything longer, or any move or resize, only handles the screen.
    private static let panelTapMaximumDuration: TimeInterval = 0.35
    private static let panelTapMaximumTravel: Float = 0.025
    private static let panelTapMaximumScaleChange: Float = 0.03

    private static func setInput(_ isEnabled: Bool, on zone: Entity) {
        guard var input = zone.components[InputTargetComponent.self],
              input.isEnabled != isEnabled else { return }
        input.isEnabled = isEnabled
        zone.components.set(input)
    }

    /// Starts a drag from where the screen is now around the viewer.
    private static func beginPanelDrag(
        panelEntity: Entity,
        gripPosition: SIMD3<Float>,
        gripScale: Float,
        measuredHand: SIMD3<Float>?,
        viewer: SIMD3<Float>
    ) -> PanelDrag {
        let panel = panelEntity.position
        var toPanel = SIMD2<Float>(panel.x - viewer.x, panel.z - viewer.z)
        let distance = max(simd_length(toPanel), panelDistanceRange.lowerBound)
        toPanel = simd_length(toPanel) > 0.001 ? simd_normalize(toPanel) : [0, -1]
        let estimatedHand = viewer
            + SIMD3<Float>(toPanel.x, 0, toPanel.y) * panelHandReach
            + SIMD3<Float>(0, -0.3, 0)
        return PanelDrag(
            lastGripPosition: gripPosition,
            hand: measuredHand ?? estimatedHand,
            handIsMeasured: measuredHand != nil,
            azimuth: atan2(toPanel.x, toPanel.y),
            distance: distance,
            height: panel.y,
            startGripScale: max(gripScale, 0.001),
            startScale: panelEntity.scale.x
        )
    }

    /// The pinching hand's position from a manipulation input, when it has
    /// one and it lies where a hand of this viewer can be. The pose's space
    /// is not documented, so anything implausible falls back to the grip.
    private static func handPosition(
        in devices: ManipulationEvents.InputDeviceSet,
        viewer: SIMD3<Float>
    ) -> SIMD3<Float>? {
        guard devices.count == 1, let pose = devices.first?.pose else { return nil }
        let hand = SIMD3<Float>(pose.position.x, pose.position.y, pose.position.z)
        let reach = simd_length(SIMD2<Float>(hand.x - viewer.x, hand.z - viewer.z))
        let rise = hand.y - viewer.y
        guard hand.x.isFinite, hand.y.isFinite, hand.z.isFinite,
              reach < 0.95, rise > -1.0, rise < 0.5 else { return nil }
        return hand
    }

    /// Follows the hand for one frame and returns where the screen goes.
    /// `measuredHand` is the tracked pinch position; without it the hand is
    /// estimated from the grip's travel.
    private static func advancePanelDrag(
        _ drag: inout PanelDrag,
        gripPosition: SIMD3<Float>,
        measuredHand: SIMD3<Float>?,
        viewer: SIMD3<Float>
    ) -> SIMD3<Float> {
        let gripStep = gripPosition - drag.lastGripPosition
        drag.lastGripPosition = gripPosition
        let previousHand = drag.hand
        if (measuredHand != nil) != drag.handIsMeasured {
            // Switching between tracked and estimated hand: start over from
            // here so the two positions cannot make the screen jump.
            drag.handIsMeasured = measuredHand != nil
            drag.lastHandAzimuth = nil
        }
        if let measuredHand {
            drag.hand = measuredHand
        } else if simd_length(gripStep) <= panelMaximumHandStep {
            drag.hand += gripStep
        }
        var step = drag.hand - previousHand
        if simd_length(step) > panelMaximumHandStep || drag.lastHandAzimuth == nil {
            step = .zero
        }

        let fromViewer = SIMD2<Float>(drag.hand.x - viewer.x, drag.hand.z - viewer.z)
        let reach = simd_length(fromViewer)
        // Right beside the body's axis the hand's angle is meaningless.
        guard reach > 0.08 else {
            drag.lastHandAzimuth = nil
            return drag.targetPosition(around: viewer)
        }
        let handAzimuth = atan2(fromViewer.x, fromViewer.y)
        if let lastHandAzimuth = drag.lastHandAzimuth {
            var turn = handAzimuth - lastHandAzimuth
            if turn > .pi { turn -= 2 * .pi }
            if turn < -.pi { turn += 2 * .pi }
            drag.azimuth += turn
        }
        drag.lastHandAzimuth = handAzimuth

        // Push and pull: the hand's travel away from the viewer. An
        // estimated hand may sit off to the side of the real one, which
        // makes a turn look partly like a push, so there only a mostly
        // outward or inward move counts.
        let outward = SIMD2<Float>(fromViewer.x, fromViewer.y) / reach
        let horizontalStep = SIMD2<Float>(step.x, step.z)
        let radialStep = simd_dot(horizontalStep, outward)
        var depthWeight: Float = 1
        if !drag.handIsMeasured {
            let stepLength = simd_length(horizontalStep)
            let straightness = stepLength > 0.0001 ? abs(radialStep) / stepLength : 0
            depthWeight = min(max((straightness - 0.6) / 0.3, 0), 1)
        }
        drag.distance = min(
            max(
                drag.distance * exp(radialStep * depthWeight * panelDepthGain),
                panelDistanceRange.lowerBound
            ),
            panelDistanceRange.upperBound
        )

        // Raising the hand lifts the screen by the same angle.
        let handReach = drag.handIsMeasured
            ? min(max(reach, 0.25), 0.6)
            : panelHandReach
        drag.height += step.y * drag.distance / handReach
        let heightLimit = drag.distance * panelMaximumElevationSlope
        drag.height = min(
            max(drag.height, viewer.y - heightLimit),
            viewer.y + heightLimit
        )
        return drag.targetPosition(around: viewer)
    }

    var body: some View {
        let effectsActive = appModel.effectsActive
        let effectsArePlaying = appModel.theMomentIsPlaying
        let particleOpacity = appModel.effectsOpacity
        let nativeMovieDimmingIsActive = appModel.experienceScreen == .theMoment
            && appModel.youtubePlaybackHasStarted
        let nativeAstrophageTintIsActive = nativeMovieDimmingIsActive
            && particleOpacity > 0.001

        return RealityView { content, attachments in
            AppTrace.mark("IMMERSIVE RealityView make begin")
            // The head pose places the screen before it fades in.
            sceneState.startWorldTracking()
            let panelGrip = Entity()
            panelGrip.name = "Screen Gesture Transform"
            panelGrip.position = Self.panelRestPosition
            panelGrip.scale = [1.5, 1.5, 1.5]
            let panelEntity = Entity()
            panelEntity.name = "Movable Screen"
            panelEntity.position = panelGrip.position
            panelEntity.scale = panelGrip.scale
            var manipulation = ManipulationComponent()
            manipulation.dynamics.translationBehavior = .unconstrained
            manipulation.dynamics.primaryRotationBehavior = .none
            manipulation.dynamics.secondaryRotationBehavior = .none
            manipulation.dynamics.scalingBehavior = .unconstrained
            manipulation.dynamics.inertia = .zero
            manipulation.releaseBehavior = .stay
            manipulation.audioConfiguration = .none
            panelGrip.components.set(manipulation)

            // The video controls cover the grab surfaces, so while they are
            // up they drive the grip themselves. Everything downstream then
            // treats it exactly like a manipulation of the screen.
            appModel.panelHandle.begin = {
                guard !sceneState.panelHandleIsActive,
                      sceneState.panelDrag == nil else { return }
                sceneState.panelHandleIsActive = true
                sceneState.panelHandleGripStartPosition = panelGrip.position
                sceneState.panelHandleGripStartScale = panelGrip.scale.x
                sceneState.panelPress = nil
                sceneState.panelHandPosition = nil
                sceneState.panelDrag = Self.beginPanelDrag(
                    panelEntity: panelEntity,
                    gripPosition: panelGrip.position,
                    gripScale: panelGrip.scale.x,
                    measuredHand: nil,
                    viewer: sceneState.viewerPosition()
                )
                appModel.panelManipulationIsActive = true
                AppTrace.mark("IMMERSIVE panel drag begin from video controls")
            }
            appModel.panelHandle.update = { translation, magnification in
                guard sceneState.panelHandleIsActive,
                      translation.x.isFinite, translation.y.isFinite,
                      translation.z.isFinite, magnification.isFinite,
                      magnification > 0 else { return }
                panelGrip.position = sceneState.panelHandleGripStartPosition + translation
                panelGrip.scale = SIMD3<Float>(
                    repeating: sceneState.panelHandleGripStartScale * magnification
                )
            }
            appModel.panelHandle.end = {
                guard sceneState.panelHandleIsActive else { return }
                sceneState.panelHandleIsActive = false
                appModel.panelManipulationIsActive = false
                sceneState.panelDrag = nil
                sceneState.panelHandPosition = nil
                panelGrip.position = sceneState.panelTargetPosition
                panelGrip.scale = panelEntity.scale
                AppTrace.mark("IMMERSIVE panel drag end from video controls")
            }

            // The start button sits low in the 1280×720 attachment (around
            // x=675, y=585). Leave its full rendered area, including margins,
            // free of panel-manipulation input so a tap can start playback.
            let upperGrabPosition: SIMD3<Float> = [0, 0.0675, -0.02]
            let upperGrabSize: SIMD3<Float> = [0.94, 0.395, 0.005]
            let grabZones: [(String, SIMD3<Float>, SIMD3<Float>)] = [
                ("Upper", upperGrabPosition, upperGrabSize),
                ("Left", [-0.31, -0.1975, -0.02], [0.32, 0.135, 0.005]),
                ("Right", [0.33, -0.1975, -0.02], [0.28, 0.135, 0.005])
            ]
            for (name, position, size) in grabZones {
                let zone = Entity()
                zone.name = "Screen Grab \(name)"
                zone.position = position
                zone.components.set(CollisionComponent(
                    shapes: [.generateBox(size: size)],
                    mode: .trigger
                ))
                zone.components.set(InputTargetComponent())
                zone.components.set(
                    ManipulationComponent.HitTarget(redirectedEntity: panelGrip)
                )
                panelEntity.addChild(zone)
                sceneState.panelGrabSurfaces.append(zone)
            }
            // During the movie there is no start button, so this fills its
            // gap and the whole screen can be grabbed. It keeps its input
            // component from the start and is only switched on and off:
            // adding input targets later makes SwiftUI re-host the panel.
            let playbackZone = Entity()
            playbackZone.name = "Screen Grab Playback Center"
            playbackZone.position = [0.02, -0.1975, -0.02]
            playbackZone.components.set(CollisionComponent(
                shapes: [.generateBox(size: [0.34, 0.135, 0.005])],
                mode: .trigger
            ))
            var playbackInput = InputTargetComponent()
            playbackInput.isEnabled = false
            playbackZone.components.set(playbackInput)
            playbackZone.components.set(
                ManipulationComponent.HitTarget(redirectedEntity: panelGrip)
            )
            panelEntity.addChild(playbackZone)
            sceneState.panelGrabSurfaces.append(playbackZone)
            sceneState.panelPlaybackGrabSurface = playbackZone

            let panelPortal = ParallaxRibbonScene(
                overlay: .warning,
                logoEntranceDistance: Self.logoEntranceDistance
            )
            panelEntity.addChild(panelPortal.world)
            panelEntity.addChild(panelPortal.portalSurface)
            panelEntity.addChild(panelPortal.logoStage)
            panelPortal.startRibbonAnimation()
            sceneState.panelPortal = panelPortal

            // A RealityView attachment, not a ViewAttachmentComponent: SwiftUI
            // in a ViewAttachmentComponent shows gaze hover but never receives
            // the pinch (verified in the simulator), so no control could be
            // tapped.
            if let panelVisual = attachments.entity(for: Self.panelAttachmentID) {
                panelVisual.name = "Viewer Facing Screen"
                panelEntity.addChild(panelVisual)
                sceneState.panelVisual = panelVisual
            }
            // Hidden until it is placed; the scene update then fades it in.
            panelEntity.components.set(OpacityComponent(opacity: 0))
            // World space, not a head anchor: a head anchor would copy the
            // head's tilt at launch into the screen.
            content.add(panelGrip)
            content.add(panelEntity)
            sceneState.panelGrip = panelGrip
            sceneState.panelEntity = panelEntity

            let physicsRoot = Entity()
            physicsRoot.name = "Menu Physics Root"
            var physics = PhysicsSimulationComponent()
            physics.gravity = .zero
            physics.collisionOptions = .reportKinematicVsKinematic
            physicsRoot.components.set(physics)

            sceneState.physicsRoot = physicsRoot
            content.add(physicsRoot)
            _ = content.subscribe(to: SceneEvents.Update.self) { event in
                guard sceneState.panelIsPlaced || sceneState.placePanelIfNeeded(
                    panelEntity: panelEntity,
                    panelGrip: panelGrip,
                    restOffset: Self.panelRestPosition,
                    windowPosition: appModel.mainWindowPositionInImmersiveSpace
                ) else { return }
                if let elapsed = sceneState.startupIntroElapsed,
                   !sceneState.panelFadeIsComplete {
                    // One clock drives the whole entrance. Capping the frame
                    // delta makes a busy frame pause the fade, never skip it.
                    let time = elapsed + min(Float(event.deltaTime), 0.05)
                    sceneState.startupIntroElapsed = time
                    let x = min(time / Self.panelFadeInDuration, 1)
                    // Smootherstep: no visible start or stop.
                    let opacity = x * x * x * (x * (x * 6 - 15) + 10)
                    panelEntity.components.set(OpacityComponent(opacity: opacity))
                    panelPortal.setStartupOverlayOpacity(opacity)
                    // App state changes only once the fade is finished, so
                    // no SwiftUI update can land in the middle of it.
                    if x >= 1 {
                        panelEntity.components.remove(OpacityComponent.self)
                        sceneState.panelFadeIsComplete = true
                        appModel.startupSequencePhase = .warning
                        appModel.startupWarningDidAppear = true
                        appModel.immersivePanelIsVisible = true
                        AppTrace.mark("IMMERSIVE warning panel fade-in complete")
                    }
                }
                // Manipulation writes the grip's transform directly. The
                // visible screen only follows the hand's movement around the
                // viewer, so a large or briefly lost hand pose cannot throw
                // it out of reach.
                let rawPosition = panelGrip.position
                guard rawPosition.x.isFinite,
                      rawPosition.y.isFinite,
                      rawPosition.z.isFinite,
                      panelGrip.scale.x.isFinite else { return }
                if var press = sceneState.panelPress, !press.changedPanel {
                    let travel = simd_distance(rawPosition, press.startPosition)
                    let scaleChange = abs(panelGrip.scale.x / press.startScale - 1)
                    if travel > Self.panelTapMaximumTravel
                        || scaleChange > Self.panelTapMaximumScaleChange {
                        press.changedPanel = true
                        sceneState.panelPress = press
                    }
                }
                let isDragging = appModel.panelManipulationIsActive
                    && sceneState.panelDrag != nil
                let viewer = isDragging
                    ? sceneState.viewerPosition()
                    : sceneState.lastViewerPosition
                if isDragging, var drag = sceneState.panelDrag {
                    sceneState.panelTargetPosition = Self.advancePanelDrag(
                        &drag,
                        gripPosition: rawPosition,
                        measuredHand: sceneState.panelHandPosition,
                        viewer: viewer
                    )
                    sceneState.panelDrag = drag
                }
                let smoothing = 1 - exp(-Float(event.deltaTime) * 12)
                panelEntity.position +=
                    (sceneState.panelTargetPosition - panelEntity.position) * smoothing
                if isDragging, let drag = sceneState.panelDrag {
                    let scaleChange = panelGrip.scale.x / drag.startGripScale
                    let scale = drag.startScale
                        * pow(max(scaleChange, 0.001), Self.panelScaleExponent)
                    let limitedScale = min(
                        max(scale, Self.panelScaleRange.lowerBound),
                        Self.panelScaleRange.upperBound
                    )
                    panelEntity.scale = SIMD3<Float>(repeating: limitedScale)
                }
                if isDragging {
                    // Turn to face the viewer about the vertical axis only:
                    // no pitch and no roll, whatever the head does.
                    let targetOrientation = ImmersiveSceneState.facing(
                        from: panelEntity.position,
                        toward: viewer
                    )
                    let turnSmoothing = 1 - exp(-Float(event.deltaTime) * 10)
                    panelEntity.orientation = simd_slerp(
                        panelEntity.orientation,
                        targetOrientation,
                        turnSmoothing
                    )
                }
                // The portal is only drawn from its front. Hide the SwiftUI
                // controls and the logo as well once the viewer is behind
                // the screen, so nothing is left floating there mirrored.
                if let panelVisual = sceneState.panelVisual {
                    let viewerDepth = panelEntity.convert(
                        position: sceneState.viewerPosition(),
                        from: nil
                    ).z
                    if viewerDepth < -0.02, !sceneState.panelVisualIsHiddenFromBehind {
                        sceneState.panelVisualIsHiddenFromBehind = true
                        panelVisual.components.set(OpacityComponent(opacity: 0))
                        panelPortal.logoStage.isEnabled = false
                    } else if viewerDepth > 0.02, sceneState.panelVisualIsHiddenFromBehind {
                        sceneState.panelVisualIsHiddenFromBehind = false
                        panelVisual.components.remove(OpacityComponent.self)
                        panelPortal.logoStage.isEnabled = true
                    }
                }
            }

            let headAnchor = AnchorEntity(
                .head,
                trackingMode: .once,
                physicsSimulation: .none
            )
            headAnchor.name = "Infrared Effects Head Anchor"

            // Level in world space and turned toward the screen once it is
            // placed; not on the head anchor, which copies the head's tilt.
            let particleRig = Entity()
            particleRig.name = "Astrophage Screen Direction Rig"
            let particleOrigin = Entity()
            particleOrigin.name = "The Moment Particle Origin"
            particleOrigin.position = Self.astrophageOriginOffset

            let particles = AstrophageParticles()
            particleOrigin.addChild(particles)
            particleRig.addChild(particleOrigin)

            let orbitingModels = OrbitingSpaceModels()
            headAnchor.addChild(orbitingModels)
            let activationBox = ActivationBox()

            // Load outside make so the screen can appear at once. The work
            // waits for the screen's fade-in, then starts before any models,
            // physics colliders or home reveal are prepared.
            sceneState.assetLoadTask = Task { @MainActor in
                // The deadline only covers a fade that never starts; a
                // running fade is always allowed to finish first.
                let fadeDeadline = ContinuousClock.now + .seconds(8)
                while !sceneState.panelFadeIsComplete,
                      sceneState.startupIntroElapsed != nil
                        || ContinuousClock.now < fadeDeadline,
                      !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard !Task.isCancelled else { return }

                physicsRoot.addChild(headAnchor)
                physicsRoot.addChild(particleRig)
                sceneState.particles = particles
                sceneState.orbitingModels = orbitingModels
                AppTrace.mark("IMMERSIVE orbiting models load begin")
                await orbitingModels.loadModels()
                AppTrace.mark("IMMERSIVE orbiting models load complete")
                guard !Task.isCancelled else { return }
                if appModel.canvasShowsFinalHomeState {
                    orbitingModels.presentHomeFinalStateImmediately()
                }
                orbitingModels.setOrbitingVisible(appModel.propsAreVisible)

                sceneState.activationBox = activationBox
                AppTrace.mark("IMMERSIVE Petrova Indicator load begin")
                await activationBox.loadModel()
                _ = await orbitingModels.addActivationBox(activationBox)
                AppTrace.mark("IMMERSIVE Petrova Indicator load complete")
                guard !Task.isCancelled else { return }
                sceneState.spatialAssetsAreLoaded = true
                appModel.immersiveExperienceAssetsPrepared = true
                AppTrace.mark("IMMERSIVE spatial experience assets prepared")
            }

            var particleOriginPlaced = false
            var handledRecenterRequestID: UUID?
            var activeParticleRig = particleRig
            var activeParticleOrigin = particleOrigin
            var activeParticles = particles
            var retiringParticleGenerations: [RetiringAstrophageGeneration] = []
            _ = content.subscribe(to: SceneEvents.Update.self) { event in
                guard sceneState.spatialAssetsAreLoaded else { return }
                let selectedScreen = appModel.experienceScreen
                if appModel.initialHomeSceneRevealIsAllowed,
                   appModel.experiencesArePrepared {
                    orbitingModels.startInitialHomeRevealIfNeeded()
                }
                let experienceHasStarted = selectedScreen == .theMoment
                    && !appModel.shouldShowStartScreen
                orbitingModels.setOrbitingVisible(appModel.propsAreVisible)
                orbitingModels.setActiveExperiencePresentation(
                    experienceHasStarted,
                    showsActivationBox: appModel.petrovaIndicatorIsUnlocked
                )
                orbitingModels.update(deltaTime: Float(event.deltaTime))
                let particlesAreVisible = appModel.effectsActive
                let particlesArePlaying = appModel.theMomentIsPlaying
                let currentParticleOpacity = appModel.effectsOpacity
                let particleDeltaTime = Float(event.deltaTime)
                activeParticles.update(deltaTime: particleDeltaTime)

                for index in retiringParticleGenerations.indices.reversed() {
                    retiringParticleGenerations[index].particles.updatePlayback(
                        isVisible: particlesAreVisible,
                        isPlaying: particlesArePlaying,
                        opacity: currentParticleOpacity
                    )
                    retiringParticleGenerations[index].particles.update(
                        deltaTime: particleDeltaTime
                    )
                    if particlesAreVisible && particlesArePlaying {
                        retiringParticleGenerations[index].elapsed += particleDeltaTime
                    }

                    let generationHasExpired = retiringParticleGenerations[index].elapsed
                        >= AstrophageParticles.retirementDuration
                    if (!particlesAreVisible
                        && retiringParticleGenerations[index].particles.isFullyFadedOut)
                        || generationHasExpired {
                        let generation = retiringParticleGenerations.remove(at: index)
                        generation.origin.removeFromParent()
                        generation.rig.removeFromParent()
                    }
                }

                activationBox.update(deltaTime: Float(event.deltaTime))
                guard sceneState.panelIsPlaced else { return }
                if !particleOriginPlaced {
                    let rigPlacement = Self.makeAstrophageRig(
                        viewer: sceneState.lastViewerPosition,
                        panel: panelEntity.position
                    )
                    particleRig.transform = rigPlacement.transform
                    activeParticles.updatePlayback(
                        isVisible: particlesAreVisible,
                        isPlaying: particlesArePlaying,
                        opacity: currentParticleOpacity
                    )
                    particleOriginPlaced = true
                    AppTrace.mark("ASTROPHAGE initial direction toward screen")
                }
                Self.followPanel(
                    rig: activeParticleRig,
                    particles: activeParticles,
                    panel: panelEntity.position,
                    panelScale: panelEntity.scale.x,
                    deltaTime: particleDeltaTime
                )

                guard let requestID = appModel.astrophageRecenterRequestID,
                      requestID != handledRecenterRequestID else { return }

                // A fresh generation from where the viewer is now, straight
                // toward the screen; the old flight keeps going and retires.
                let recenterRig = Self.makeAstrophageRig(
                    viewer: sceneState.viewerPosition(),
                    panel: panelEntity.position
                )
                physicsRoot.addChild(recenterRig)

                activeParticles.retireAfterRecenter(
                    isVisible: particlesAreVisible,
                    isPlaying: particlesArePlaying,
                    opacity: currentParticleOpacity
                )
                retiringParticleGenerations.append(
                    RetiringAstrophageGeneration(
                        particles: activeParticles,
                        origin: activeParticleOrigin,
                        rig: activeParticleRig
                    )
                )

                let newParticleOrigin = Entity()
                newParticleOrigin.name = "The Moment Particle Origin"
                newParticleOrigin.transform = Transform(
                    translation: Self.astrophageOriginOffset
                )
                let newParticles = AstrophageParticles()
                newParticleOrigin.addChild(newParticles)
                recenterRig.addChild(newParticleOrigin)
                newParticles.beginAfterRecenter(
                    isVisible: particlesAreVisible,
                    isPlaying: particlesArePlaying,
                    opacity: currentParticleOpacity
                )
                Self.followPanel(
                    rig: recenterRig,
                    particles: newParticles,
                    panel: panelEntity.position,
                    panelScale: panelEntity.scale.x,
                    deltaTime: 0
                )

                activeParticleOrigin = newParticleOrigin
                activeParticles = newParticles
                activeParticleRig = recenterRig
                sceneState.particles = newParticles
                handledRecenterRequestID = requestID
                AppTrace.mark("ASTROPHAGE fresh direction fading in; old flight retiring")
            }

            _ = content.subscribe(to: ManipulationEvents.WillBegin.self) { event in
                if event.entity === panelGrip {
                    appModel.panelManipulationIsActive = true
                    sceneState.panelPress = PanelPress(
                        startTime: CACurrentMediaTime(),
                        startPosition: panelGrip.position,
                        startScale: panelGrip.scale.x
                    )
                    let viewer = sceneState.viewerPosition()
                    let hand = Self.handPosition(in: event.inputDeviceSet, viewer: viewer)
                    sceneState.panelHandPosition = hand
                    sceneState.panelDrag = Self.beginPanelDrag(
                        panelEntity: panelEntity,
                        gripPosition: panelGrip.position,
                        gripScale: panelGrip.scale.x,
                        measuredHand: hand,
                        viewer: viewer
                    )
                    AppTrace.mark(
                        "IMMERSIVE panel drag begin hand="
                            + (hand == nil ? "estimated" : "tracked")
                    )
                    return
                }
                guard sceneState.spatialAssetsAreLoaded else { return }
                if activationBox.contains(event.entity) {
                    activationBox.beginGrab()
                }
                orbitingModels.beginGrab(event.entity)
            }

            _ = content.subscribe(to: ManipulationEvents.DidUpdateTransform.self) { event in
                guard event.entity === panelGrip, sceneState.panelDrag != nil else { return }
                sceneState.panelHandPosition = Self.handPosition(
                    in: event.inputDeviceSet,
                    viewer: sceneState.lastViewerPosition
                )
            }

            _ = content.subscribe(to: ManipulationEvents.DidHandOff.self) { event in
                guard sceneState.spatialAssetsAreLoaded else { return }
                orbitingModels.noteGrabHandOff(event.entity)
            }

            _ = content.subscribe(to: ManipulationEvents.WillRelease.self) { event in
                if event.entity === panelGrip {
                    appModel.panelManipulationIsActive = false
                    sceneState.panelDrag = nil
                    sceneState.panelHandPosition = nil
                    guard let press = sceneState.panelPress else { return }
                    sceneState.panelPress = nil
                    let duration = CACurrentMediaTime() - press.startTime
                    if !event.wasCancelled,
                       !press.changedPanel,
                       duration < Self.panelTapMaximumDuration {
                        AppTrace.mark("IMMERSIVE panel tapped")
                        appModel.panelTapCount += 1
                    } else {
                        AppTrace.mark(
                            "IMMERSIVE panel handled without tap "
                                + "moved=\(press.changedPanel) "
                                + "held=\(String(format: "%.2f", duration))s"
                        )
                    }
                    return
                }
                guard sceneState.spatialAssetsAreLoaded else { return }
                if activationBox.contains(event.entity) {
                    guard activationBox.hasActiveGrab else { return }
                    activationBox.endGrab()
                }
                if event.wasCancelled {
                    // A transient tracking loss is not a user release. Keep
                    // the model held so it cannot unexpectedly start drifting.
                    orbitingModels.keepGrabAfterCancellation(event.entity)
                } else {
                    orbitingModels.endGrab(event.entity)
                }
            }

            _ = content.subscribe(to: ManipulationEvents.WillEnd.self) { event in
                if event.entity === panelGrip {
                    appModel.panelManipulationIsActive = false
                    sceneState.panelPress = nil
                    sceneState.panelDrag = nil
                    sceneState.panelHandPosition = nil
                    Task { @MainActor in
                        await Task.yield()
                        panelGrip.position = sceneState.panelTargetPosition
                        panelGrip.scale = panelEntity.scale
                    }
                }
            }

            _ = content.subscribe(to: CollisionEvents.Began.self) { event in
                guard sceneState.spatialAssetsAreLoaded else { return }
                let contact = event.contacts.first
                orbitingModels.queueModelCollision(
                    between: event.entityA,
                    and: event.entityB,
                    contactPoint: contact?.point ?? event.position,
                    contactNormal: contact?.normal,
                    penetration: contact?.penetrationDistance ?? 0
                )
            }
            _ = content.subscribe(to: CollisionEvents.Updated.self) { event in
                guard sceneState.spatialAssetsAreLoaded else { return }
                let contact = event.contacts.max { $0.penetrationDistance < $1.penetrationDistance }
                orbitingModels.queueModelCollision(
                    between: event.entityA, and: event.entityB,
                    contactPoint: contact?.point ?? event.position,
                    contactNormal: contact?.normal,
                    penetration: contact?.penetrationDistance ?? 0
                )
            }
            AppTrace.mark("IMMERSIVE RealityView make complete")
        } update: { _, _ in
            if let bounds = sceneState.panelVisual?.components[ViewAttachmentComponent.self]?.bounds,
               bounds.extents.x > 0,
               let panelPortal = sceneState.panelPortal {
                panelPortal.fitPortal(to: BoundingBox(
                    min: [bounds.min.x, bounds.min.y, bounds.min.z - 0.013],
                    max: [bounds.max.x, bounds.max.y, bounds.max.z]
                ))
                if !sceneState.panelFadeInScheduled {
                    sceneState.panelFadeInScheduled = true
                    AppTrace.mark(
                        "IMMERSIVE panel attachment bounds "
                            + "x=\(bounds.min.x)...\(bounds.max.x) "
                            + "y=\(bounds.min.y)...\(bounds.max.y)"
                    )
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        // Appear only once placed level in front of the
                        // viewer; without a head pose in time, in front of
                        // the space's origin.
                        let placementStart = ContinuousClock.now
                        let placementDeadline = placementStart + Self.panelPlacementTimeout
                        while !sceneState.panelIsPlaced,
                              ContinuousClock.now < placementDeadline {
                            // With a head pose but no launch window position
                            // in time, the head's direction has to do.
                            if ContinuousClock.now - placementStart > Self.panelWindowPositionTimeout,
                               sceneState.currentDeviceTransform() != nil { break }
                            try? await Task.sleep(for: .milliseconds(30))
                        }
                        if let panelEntity = sceneState.panelEntity,
                           let panelGrip = sceneState.panelGrip {
                            sceneState.placePanelIfNeeded(
                                panelEntity: panelEntity,
                                panelGrip: panelGrip,
                                restOffset: Self.panelRestPosition,
                                windowPosition: appModel.mainWindowPositionInImmersiveSpace,
                                useFallback: true
                            )
                        }
                        guard appModel.mainWindowIsOpen else { return }
                        sceneState.startupIntroElapsed = 0
                        AppTrace.mark("IMMERSIVE warning panel fade-in begin")
                    }
                }
            }
            if let panelPortal = sceneState.panelPortal {
                let presentation = PanelPortalPresentation(appModel: appModel)
                panelPortal.setEffectOpacity(
                    presentation.effectOpacity,
                    fadeDuration: AppModel.homeReturnRevealDuration
                )
                panelPortal.setOverlay(
                    presentation.overlay,
                    opacity: presentation.overlayOpacity,
                    fadeDuration: presentation.overlayFadeDuration
                )
                if appModel.startupPreloadReleased {
                    panelPortal.prewarmOverlayMaterials()
                }
            }
            if let panelGrip = sceneState.panelGrip {
                // Keep the grab input stable otherwise: every first
                // appearance of input targets makes SwiftUI re-host the
                // panel attachment.
                let controlsClaimInput = appModel.theMomentControlsAreVisible
                    || appModel.scrubberIsHovered
                    || appModel.scrubberIsEditing
                if controlsClaimInput {
                    if appModel.theMomentControlsAreVisible,
                       panelGrip.components[ManipulationComponent.self] != nil {
                        AppTrace.mark("IMMERSIVE panel manipulation released for video controls")
                    }
                    panelGrip.components.remove(ManipulationComponent.self)
                    for zone in sceneState.panelGrabSurfaces {
                        Self.setInput(false, on: zone)
                    }
                    // With the controls up, the controls themselves move and
                    // resize the screen (`panelHandle`); leave that alone.
                    if !sceneState.panelHandleIsActive {
                        sceneState.panelPress = nil
                        sceneState.panelDrag = nil
                        sceneState.panelHandPosition = nil
                        if appModel.panelManipulationIsActive {
                            appModel.panelManipulationIsActive = false
                        }
                    }
                } else {
                    // Home keeps the start button's area free for its tap;
                    // during the movie the whole screen can be grabbed.
                    let movieOwnsScreen = !appModel.shouldShowStartScreen
                    for zone in sceneState.panelGrabSurfaces {
                        let isPlaybackZone = zone === sceneState.panelPlaybackGrabSurface
                        Self.setInput(!isPlaybackZone || movieOwnsScreen, on: zone)
                    }
                    if panelGrip.components[ManipulationComponent.self] == nil {
                        var manipulation = ManipulationComponent()
                        manipulation.dynamics.translationBehavior = .unconstrained
                        manipulation.dynamics.primaryRotationBehavior = .none
                        manipulation.dynamics.secondaryRotationBehavior = .none
                        manipulation.dynamics.scalingBehavior = .unconstrained
                        manipulation.dynamics.inertia = .zero
                        manipulation.releaseBehavior = .stay
                        manipulation.audioConfiguration = .none
                        panelGrip.components.set(manipulation)
                    }
                }
            }
            if appModel.experienceScreen == .menu && appModel.experiencesArePrepared {
                sceneState.orbitingModels?.startInitialHomeRevealIfNeeded()
            }
            let experienceHasStarted = appModel.experienceScreen == .theMoment
                && !appModel.shouldShowStartScreen
            sceneState.orbitingModels?.setOrbitingVisible(
                appModel.propsAreVisible
            )
            sceneState.orbitingModels?.setActiveExperiencePresentation(
                experienceHasStarted,
                showsActivationBox: appModel.petrovaIndicatorIsUnlocked
            )
            sceneState.activationBox?.setAstrophageActivated(
                appModel.activationBoxIsActivated
            )
            sceneState.activationBox?.setInfraredFilterOpacity(
                Float(appModel.effectsOpacity)
            )
            sceneState.orbitingModels?.setInfraredFilterOpacity(
                Float(appModel.effectsOpacity)
            )

            guard let physicsRoot = sceneState.physicsRoot,
                  physicsRoot.children.contains(where: { $0.name == "Infrared Effects Head Anchor" }),
                  let particles = sceneState.particles else {
                return
            }

            particles.updatePlayback(
                isVisible: effectsActive,
                isPlaying: effectsArePlaying,
                opacity: particleOpacity
            )
        } attachments: {
            Attachment(id: Self.panelAttachmentID) {
                ExperiencePanelView(
                    isImmersiveAttachment: true,
                    retryAction: {}
                )
                .environment(appModel)
            }
        }
        .onChange(of: appModel.experienceScreen) { oldScreen, newScreen in
            AppTrace.mark("IMMERSIVE screen \(oldScreen) -> \(newScreen)")
        }
        .onChange(of: appModel.immersiveCloseRequestID, initial: true) { _, requestID in
            guard let requestID else { return }

            Task { @MainActor in
                await dismissImmersiveSpace()
                guard appModel.immersiveCloseRequestID == requestID else { return }
                appModel.immersiveCloseRequestID = nil
                appModel.immersiveCloseRequestInFlight = false
                appModel.immersiveSpaceState = .closed
            }
        }
        .onDisappear {
            sceneState.assetLoadTask?.cancel()
            sceneState.worldTrackingSession.stop()
        }
        .onChange(of: nativeMovieDimmingIsActive, initial: true) { _, isActive in
            AppTrace.mark(
                "IMMERSIVE native surroundings preference "
                    + (isActive ? "ultraDark" : "none")
            )
        }
        // This is the only surroundings preference in the app. Read the
        // playback flag directly in this root view so SwiftUI reevaluates the
        // native preference before any Astrophage RealityKit effects appear.
        .preferredSurroundingsEffect(
            nativeMovieDimmingIsActive
                ? (nativeAstrophageTintIsActive
                    ? .colorMultiply(Color(
                        red: 0.40,
                        green: 0.055,
                        blue: 0.035
                    ))
                    : .ultraDark)
                : nil
        )
    }

}

#Preview("Home — final state", immersionStyle: .mixed) {
    let appModel = AppModel()
    appModel.immersiveSpaceState = .open
    appModel.experienceScreen = .menu
    appModel.immersiveExperienceAssetsPrepared = true
    appModel.mediaExperiencePrepared = true
    appModel.propsAreVisible = true
    appModel.canvasShowsFinalHomeState = true

    return ImmersiveView()
        .environment(appModel)
}
