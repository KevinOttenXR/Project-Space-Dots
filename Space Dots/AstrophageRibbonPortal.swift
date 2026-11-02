import RealityKit
import SwiftUI
import UIKit

enum AstrophagePortalOverlay: Equatable {
    case none
    case warning
    case loading
    case handoff
    case home
}

/// A masked RealityKit portal with animated ribbons and a flush visual layer.
///
/// The plane itself is the mask: only the separate portal world can render
/// through it. The world contains an overscanned ribbon layer at depth, so
/// there are no visible walls, box edges, or a separate 3D object to see.
struct AstrophageRibbonPortalView: View {

    /// Drives only the astrophage and grain layers. The black portal opening
    /// remains visible at zero so it can sit behind the launch warning.
    private let effectOpacity: Double
    private let effectFadeDuration: Double
    private let overlay: AstrophagePortalOverlay
    private let overlayOpacity: Double
    private let overlayFadeDuration: Double
    private let prewarmStaticOverlays: Bool
    private let onReady: () -> Void
    @State private var scene: ParallaxRibbonScene

    init(
        effectOpacity: Double = 1.0,
        effectFadeDuration: Double = 0.8,
        overlay: AstrophagePortalOverlay = .home,
        overlayOpacity: Double = 1.0,
        overlayFadeDuration: Double = 0.8,
        prewarmStaticOverlays: Bool = false,
        onReady: @escaping () -> Void = {}
    ) {
        self.effectOpacity = effectOpacity
        self.effectFadeDuration = effectFadeDuration
        self.overlay = overlay
        self.overlayOpacity = overlayOpacity
        self.overlayFadeDuration = overlayFadeDuration
        self.prewarmStaticOverlays = prewarmStaticOverlays
        self.onReady = onReady
        _scene = State(
            initialValue: ParallaxRibbonScene(
                overlay: overlay
            )
        )
    }

    var body: some View {
        GeometryReader3D { geometry in
            RealityView { content in
                content.add(scene.world)
                content.add(scene.portalSurface)
                scene.startRibbonAnimation()
                Task { @MainActor in
                    // Keep the lightweight black first frame through the
                    // first portal draw, then remove that temporary backing.
                    try? await Task.sleep(for: .milliseconds(150))
                    onReady()
                }
            } update: { content in
                let bounds = content.convert(
                    geometry.frame(in: .local),
                    from: .local,
                    to: .scene
                )
                scene.fitPortal(to: bounds)
                scene.setEffectOpacity(
                    effectOpacity,
                    fadeDuration: effectFadeDuration
                )
                scene.setOverlay(
                    overlay,
                    opacity: overlayOpacity,
                    fadeDuration: overlayFadeDuration
                )
                if prewarmStaticOverlays {
                    scene.prewarmOverlayMaterials()
                }
            }
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: ExperienceUIStyle.panelCornerRadius,
                style: .continuous
            )
        )
        .accessibilityLabel("Ribbon panel")
    }
}

/// The Home overlay shown after loading.
private struct PortalHomeFinalStateOverlay: View {

    var body: some View {
        ZStack {
            // The logo is not baked in here: the vector logo layers stay on
            // screen at their final transform above this texture.
            VStack(alignment: .leading, spacing: 28) {
                Text(
                    "Relive Grace's moment with the astrophage. Please take a seat before you start, statement."
                )
                .font(.system(size: 25, weight: .regular, design: .default))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineSpacing(9)
                .frame(maxWidth: 560, alignment: .leading)

                Color.clear
                    .frame(
                        width: ExperienceUIStyle.primaryButtonMinimumWidth,
                        height: ExperienceUIStyle.primaryButtonHeight
                    )
                    .scaleEffect(0.8, anchor: .topLeading)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(.trailing, 100)
            .padding(.bottom, 100)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .bottomTrailing
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PortalWarningOverlay: View {
    var body: some View {
        VStack(spacing: 34) {
            Text("WARNING")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(.white)

            VStack(spacing: 28) {
                Text(
                    "This experience contains intense motion and sequences of flashing lights that may cause discomfort or trigger seizures for people with photosensitivities."
                )
                Text("Viewer discretion is advised.")
            }
            .font(.system(size: 25, weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(8)
            .frame(maxWidth: 900)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 120)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One line of the SPACE DOTS logo, matching `SpaceDotsTitleTreatment`.
private enum PortalLogoLine {
    case title
    case project

    var text: String {
        switch self {
        case .title: return "SPACE DOTS"
        case .project: return "PROJECT"
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .title: return 78
        case .project: return 22
        }
    }

    var tracking: CGFloat {
        switch self {
        case .title: return 7
        case .project: return 8
        }
    }

    var uiFontWeight: UIFont.Weight {
        switch self {
        case .title: return .semibold
        case .project: return .medium
        }
    }

    var color: Color {
        switch self {
        case .title: return .white
        case .project: return ExperienceUIStyle.primaryRed
        }
    }
}

private struct PortalHandoffContentOverlay: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(
                "Relive Grace's moment with the astrophage. Please take a seat before you start, statement."
            )
            .font(.system(size: 25, weight: .regular, design: .default))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .lineSpacing(9)
            .frame(maxWidth: 560, alignment: .leading)

            Color.clear
                .frame(
                    width: ExperienceUIStyle.primaryButtonMinimumWidth,
                    height: ExperienceUIStyle.primaryButtonHeight
                )
                .scaleEffect(0.8, anchor: .topLeading)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: 600, alignment: .leading)
        .padding(.trailing, 100)
        .padding(.bottom, 100)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .bottomTrailing
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A fine, static film layer. It is materialized separately from the ribbons
/// so it stays crisp over their blur but below the portal's UI texture.
private struct PortalFilmGrainOverlay: View {

    private static let grainCount = 2_400
    let frame: Double

    var body: some View {
        Canvas(opaque: false, colorMode: .linear) { context, size in
            context.blendMode = .plusLighter

            for index in 0..<Self.grainCount {
                let seed = Double(index)
                let x = size.width * CGFloat(
                    Self.stableRandom(seed * 1.41 + frame * 0.19)
                )
                let y = size.height * CGFloat(
                    Self.stableRandom(seed * 2.73 + frame * 0.31)
                )
                let brightness = Self.stableRandom(seed * 4.19 + frame)
                let pointSize: CGFloat = brightness > 0.84 ? 0.90 : 0.56
                let opacity = 0.018 + (brightness * 0.042)
                let point = CGRect(
                    x: x,
                    y: y,
                    width: pointSize,
                    height: pointSize
                )
                context.fill(
                    Path(ellipseIn: point),
                    with: .color(.white.opacity(opacity))
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func stableRandom(_ seed: Double) -> Double {
        let value = sin((seed + 0.37) * 12.9898) * 43_758.5453
        return value - floor(value)
    }
}

@MainActor
final class ParallaxRibbonScene {

    // The final image is deliberately soft, so this lower-resolution source
    // removes work at every refresh without costing visible detail.
    private static let textureSize = CGSize(width: 640, height: 360)
    private static let basePlaneWidth: Float = 2.18
    private static let basePlaneHeight: Float = 1.248
    // Matches 28 points on the 1,280 point-wide Home panel.
    private static let portalCornerRadius: Float = 0.048
    private static let ribbonDepth: Float = -0.22
    private static let portalBlackDepth: Float = -0.225
    // UI is intentionally almost flush with the portal opening. Title,
    // Project and Home content share this plane so side viewing never adds
    // a different parallax/depth treatment to any piece of interface.
    private static let grainDepth: Float = -0.020
    private static let homeUIDepth: Float = -0.008
    // The vector logo glyphs sit this far in front of the portal UI plane.
    private static let logoTextLift: Float = 0.001
    // PROJECT (22 pt) lands at 18.7 pt, where its capitals are as tall as
    // the lowercase letters of the 25 pt Home copy, so the two read as the
    // same size. SPACE DOTS (78 pt) lands at 45 pt. The whole lockup is
    // then enlarged by `homeLogoEnlargement` about its top-leading corner.
    private static let homeLogoEnlargement: Float = 1.38
    // Top-leading corner of the Home lockup on the portal plane, and the
    // distance from that top edge down to each line's centre before the
    // enlargement. The corner stays put whatever the enlargement is.
    // The leading inset matches the top inset (0.202 from the plane edge).
    private static let homeLogoLeadingEdge: Float = -0.888
    private static let homeLogoTopEdge: Float = 0.422
    private static let homeTitleCentreDrop: Float = 0.078
    private static let homeProjectCentreDrop: Float = 0.011
    // Half-widths of SPACE DOTS and PROJECT at scale 1.
    private static let titleHalfWidth: Float = 0.440
    private static let projectHalfWidth: Float = 0.121
    private static let homeProjectScale: Float = 18.7 / 22.0 * homeLogoEnlargement
    private static let homeTitleScale: Float = 45.0 / 78.0 * homeLogoEnlargement
    // Size, in points, of the SwiftUI layouts rendered onto the portal plane.
    private static let portalUISize = CGSize(width: 1_280, height: 720)
    // No portal layer reads or writes depth, so without an explicit order
    // RealityKit sorts them by distance to the viewer. Seen from the side,
    // the small logo meshes can then be farther away than the centre of the
    // large ribbon planes and get painted over. One shared group fixes the
    // draw order for every viewing angle.
    private static let portalSortGroup = ModelSortGroup()
    private static let horizontalOverscan: Float = 3.50
    private static let verticalOverscan: Float = 1.45
    private static let portalPatternScale: CGFloat = 0.72
    // Handoff transforms are driven by this tick; keep it at display cadence
    // so the title's move is not visibly quantised at 30 fps.
    private static let animationTickRate = 60.0
    private static let textureRefreshRate = 2.0
    private static let ribbonMotionRate = 1.0
    private static let crossfadeDuration = 0.46
    private static let grainFrameCount = 8
    private static let grainFrameRate = 12.0
    private static let homeHandoffDuration = AppModel.initialLogoMoveDuration
    private static let homeContentFadeDuration = AppModel.initialHomeRevealDuration
    private static let handoffToHomeFadeDuration = 0.25

    /// This is a RealityKit portal surface, not a visible frame or box.
    let portalSurface: ModelEntity
    /// Everything under this entity is clipped by `portalSurface`.
    let world = Entity()
    /// Shares `world`'s transform but sits outside the portal world, so the
    /// logo can float in front of the frame during its entrance. Only hosts
    /// that pass a `logoEntranceDistance` need to add it to their scene.
    let logoStage = Entity()
    /// How far in front of the portal, in metres, the centred logo starts.
    private let logoEntranceDistance: Float
    // A logo on the stage stays there for good and comes to rest just in
    // front of the portal plane. The portal world renders the same material
    // darker, so any handover to it shows as a jump in brightness.
    private static let logoStageRestDepth: Float = 0.014
    // Dims a logo on the stage towards the darker look of the Home copy
    // inside the portal. Tuned by eye; 1 leaves it at full brightness.
    private static let logoStageBrightness: CGFloat = 0.8
    private let portalBlackLayer: ModelEntity
    private let ribbonLayer: ModelEntity
    private let ribbonCrossfadeLayer: ModelEntity
    private let grainLayer: ModelEntity
    private let grainCrossfadeLayer: ModelEntity
    private let homeUILayer: ModelEntity
    private let warningOverlayMaterial: UnlitMaterial
    private var homeOverlayMaterial: UnlitMaterial?
    // The logo layers persist through loading, handoff and Home, so the
    // vector glyphs never swap for a differently rendered copy.
    private let logoTitleLayer: ModelEntity
    private let logoProjectLayer: ModelEntity
    private let handoffContentLayer: ModelEntity
    private var logoFollowsOverlay = false
    private var lastTextureFrame: Int?
    private var incomingTexture: TextureResource?
    private var crossfadeStart: Date?
    private var grainTextures: [TextureResource?] = []
    private var lastGrainFrame = -1
    // The grain runs on its own clock, independent of the ribbon animation
    // that pauses outside Home.
    private let grainClockStart = Date()
    private var effectOpacity: Float = 1
    private var targetEffectOpacity: Float = 1
    private var effectTransitionStart: Date?
    private var effectTransitionStartOpacity: Float = 1
    private var effectTransitionDuration = 0.0
    private var currentOverlay: AstrophagePortalOverlay = .home
    private var overlayOpacity: Float = 1
    private var targetOverlayOpacity: Float = 1
    private var overlayTransitionStart: Date?
    private var overlayTransitionStartOpacity: Float = 1
    private var overlayTransitionDuration = 0.0
    private var handoffStart: Date?
    private var handoffToHomeStart: Date?
    private var effectAnimationElapsed: Double = 0
    private var effectAnimationLastTick = Date()
    private var effectAnimationIsPaused: Bool
    private var animationTimer: Timer?

    init(overlay: AstrophagePortalOverlay, logoEntranceDistance: Float = 0) {
        self.logoEntranceDistance = logoEntranceDistance
        logoStage.name = "Portal logo entrance stage"
        effectAnimationIsPaused = overlay != .home
        let initialEffectOpacity: Float = overlay == .home ? 1 : 0
        effectOpacity = initialEffectOpacity
        targetEffectOpacity = initialEffectOpacity
        effectTransitionStartOpacity = initialEffectOpacity
        // Only the first visible frame is rendered during construction.
        // Preparing every later texture here makes the system launch
        // placeholder linger before our black warning panel appears.
        let warningMaterial = Self.makeOverlayMaterial(.warning)
        warningOverlayMaterial = warningMaterial
        homeOverlayMaterial = nil
        let initialOverlayMaterial: UnlitMaterial
        switch overlay {
        case .warning:
            initialOverlayMaterial = warningMaterial
        case .home:
            initialOverlayMaterial = Self.makeOverlayMaterial(.home)
        case .loading, .handoff, .none:
            initialOverlayMaterial = Self.makeOverlayMaterial(.none)
        }
        portalSurface = ModelEntity(
            mesh: Self.makeRoundedPortalMesh(),
            materials: [PortalMaterial()]
        )
        portalSurface.name = "Astrophage ribbon mask portal"

        // `WorldComponent` marks this hierarchy as separate from the normal
        // RealityView world. It can only be seen via the portal plane above.
        world.components.set(WorldComponent())
        world.name = "Astrophage portal world"
        portalSurface.components.set(PortalComponent(target: world))

        // This layer keeps the portal visibly black while its animated
        // contents are intentionally disabled (for example, during warning).
        portalBlackLayer = ModelEntity(
            mesh: .generatePlane(
                width: Self.basePlaneWidth * Self.horizontalOverscan,
                height: Self.basePlaneHeight * Self.verticalOverscan
            ),
            materials: [Self.makePortalBlackMaterial()]
        )
        portalBlackLayer.name = "Portal blackout layer"
        portalBlackLayer.position.z = Self.portalBlackDepth

        // Overscan is intentional. The portal plane masks it, but viewing the
        // panel from the side reveals more of the moving ribbon field.
        ribbonLayer = ModelEntity(
            mesh: .generatePlane(
                width: Self.basePlaneWidth * Self.horizontalOverscan,
                height: Self.basePlaneHeight * Self.verticalOverscan
            ),
            materials: [
                Self.makeRibbonMaterial(
                    texture: Self.makeRibbonTexture(elapsed: 0)
                )
            ]
        )
        ribbonLayer.name = "Astrophage ribbon depth layer"
        ribbonLayer.position.z = Self.ribbonDepth

        // A second, nearly coplanar layer eases each bitmap frame over the
        // prior one. It turns the low-cost texture updates into an apparently
        // continuous flow instead of visible frame stepping.
        ribbonCrossfadeLayer = ModelEntity(
            mesh: .generatePlane(
                width: Self.basePlaneWidth * Self.horizontalOverscan,
                height: Self.basePlaneHeight * Self.verticalOverscan
            ),
            materials: [Self.makeRibbonMaterial(texture: nil, opacity: 0)]
        )
        ribbonCrossfadeLayer.name = "Astrophage ribbon crossfade layer"
        ribbonCrossfadeLayer.position.z = Self.ribbonDepth + 0.0001

        // Positioned after the blurred ribbon planes but before the UI layer.
        // Its grain is therefore a flat overlay on the portal background.
        grainLayer = ModelEntity(
            mesh: .generatePlane(
                width: Self.basePlaneWidth,
                height: Self.basePlaneHeight
            ),
            materials: [Self.makeGrainMaterial(texture: nil, opacity: 0)]
        )
        grainLayer.name = "Film grain above portal ribbons"
        grainLayer.position.z = Self.grainDepth

        grainCrossfadeLayer = ModelEntity(
            mesh: .generatePlane(
                width: Self.basePlaneWidth,
                height: Self.basePlaneHeight
            ),
            materials: [Self.makeGrainMaterial(texture: nil, opacity: 0)]
        )
        grainCrossfadeLayer.name = "Film grain crossfade layer"
        grainCrossfadeLayer.position.z = Self.grainDepth + 0.0001

        // This transparent texture is nearly flush with the portal opening.
        // It therefore reads as UI printed on the portal rather than a card
        // floating in front of the window.
        homeUILayer = ModelEntity(
            mesh: .generatePlane(
                width: Self.basePlaneWidth,
                height: Self.basePlaneHeight
            ),
            materials: [initialOverlayMaterial]
        )
        homeUILayer.name = "Portal visual overlay"
        homeUILayer.position.z = Self.homeUIDepth
        homeUILayer.components.set(
            OpacityComponent(opacity: overlay == .none || overlay == .warning ? 0 : 1)
        )

        // Each logo line is a vector text mesh under its own layer entity.
        // RealityKit only transforms/fades them, which leaves the ribbon
        // renderer uninterrupted and keeps the glyphs sharp.
        let logoBrightness = logoEntranceDistance > 0
            ? Self.logoStageBrightness
            : 1
        logoTitleLayer = Self.makeLogoLayer(
            .title,
            sortOrder: 7
        )
        logoProjectLayer = Self.makeLogoLayer(
            .project,
            sortOrder: 8,
            brightness: logoBrightness
        )

        handoffContentLayer = ModelEntity(
            mesh: .generatePlane(
                width: Self.basePlaneWidth,
                height: Self.basePlaneHeight
            ),
            materials: [Self.makeHandoffContentMaterial()]
        )
        handoffContentLayer.name = "Portal handoff Home content"
        handoffContentLayer.position.z = Self.homeUIDepth
        handoffContentLayer.components.set(OpacityComponent(opacity: 0))

        world.addChild(portalBlackLayer)
        world.addChild(ribbonLayer)
        world.addChild(ribbonCrossfadeLayer)
        world.addChild(grainLayer)
        world.addChild(grainCrossfadeLayer)
        world.addChild(homeUILayer)
        world.addChild(logoTitleLayer)
        world.addChild(logoProjectLayer)
        world.addChild(handoffContentLayer)

        // Back-to-front draw order; the logo meshes take 7 and 8.
        let orderedLayers = [
            portalBlackLayer,
            ribbonLayer,
            ribbonCrossfadeLayer,
            grainLayer,
            grainCrossfadeLayer,
            homeUILayer,
            handoffContentLayer
        ]
        for (order, layer) in orderedLayers.enumerated() {
            layer.components.set(
                ModelSortGroupComponent(
                    group: Self.portalSortGroup,
                    order: Int32(order)
                )
            )
        }

        // Prebuild a small looping film-grain sequence once. Playback below
        // only changes material opacity, avoiding recurring render spikes.
        grainTextures = (0..<Self.grainFrameCount).map {
            Self.makeGrainTexture(frame: Double($0))
        }
        if let firstTexture = grainTextures.first ?? nil {
            grainLayer.model?.materials = [
                Self.makeGrainMaterial(texture: firstTexture)
            ]
        }
        applyEffectMaterials()

        currentOverlay = overlay
        overlayOpacity = overlay == .none || overlay == .warning ? 0 : 1
        targetOverlayOpacity = overlayOpacity

        logoFollowsOverlay = overlay == .loading || overlay == .home
        applyLogoTransform(progress: overlay == .loading ? 0 : 1)
        setLogoOpacity(logoFollowsOverlay ? overlayOpacity : 0)
    }

    func setEffectOpacity(_ opacity: Double, fadeDuration: Double) {
        let clampedOpacity = Float(min(max(opacity, 0), 1))
        guard abs(clampedOpacity - targetEffectOpacity) > 0.0005 else {
            return
        }
        targetEffectOpacity = clampedOpacity

        // A disappearance should immediately expose the pure black portal.
        // Reveals interpolate in RealityKit itself, avoiding reliance on a
        // SwiftUI update closure being called every animation frame.
        guard clampedOpacity > effectOpacity, fadeDuration > 0 else {
            effectTransitionStart = nil
            applyEffectOpacity(clampedOpacity)
            return
        }

        effectTransitionStartOpacity = effectOpacity
        effectTransitionDuration = fadeDuration
        effectTransitionStart = Date()
    }

    func setOverlay(
        _ overlay: AstrophagePortalOverlay,
        opacity: Double,
        fadeDuration: Double
    ) {
        setEffectAnimationPaused(overlay != .home)

        let targetOpacity = Float(min(max(opacity, 0), 1))
        let overlayChanged = overlay != currentOverlay
        if overlayChanged {
            let wasHandoff = currentOverlay == .handoff
            let wasHome = currentOverlay == .home
            currentOverlay = overlay
            handoffStart = overlay == .handoff ? Date() : nil
            handoffToHomeStart = nil

            if overlay == .handoff {
                // The logo is already at its centred loading position; from
                // here RealityKit moves it. Start the ribbon reveal from this
                // same handoff clock.
                effectTransitionStart = nil
                targetEffectOpacity = 0
                applyEffectOpacity(0)
                logoFollowsOverlay = false
                applyOverlayOpacity(0)
                applyHandoffState(progress: 0)
                freezeEffectFrames()
            } else if overlay == .loading {
                // Keep the prepared ribbon frame still and hidden beneath
                // the centred logo until the handoff begins.
                freezeEffectFrames()
                setHandoffContentOpacity(0)
                applyLogoTransform(progress: 0)
                logoFollowsOverlay = true
                homeUILayer.model?.materials = [Self.makeOverlayMaterial(.none)]
                applyOverlayOpacity(0)
            } else if wasHandoff && overlay == .home {
                // Crossfade the handoff copy into the Home texture. The logo
                // itself stays put at its final transform, so nothing pops.
                homeUILayer.model?.materials = [
                    homeOverlayMaterial ?? Self.makeOverlayMaterial(.home)
                ]
                applyLogoTransform(progress: 1)
                setLogoOpacity(1)
                logoFollowsOverlay = false
                applyOverlayOpacity(0)
                targetOverlayOpacity = targetOpacity
                overlayTransitionStart = nil
                handoffToHomeStart = Date()
                return
            } else if wasHome && overlay == .none {
                // Keep the last Home frame while it fades beneath the video.
                // Replacing its material with clear here exposes a black
                // frame before the video surface has finished fading in.
                targetOverlayOpacity = targetOpacity
                overlayTransitionStartOpacity = overlayOpacity
                overlayTransitionDuration = fadeDuration
                overlayTransitionStart = fadeDuration > 0 ? Date() : nil
                if fadeDuration <= 0 { applyOverlayOpacity(targetOpacity) }
                return
            } else {
                setHandoffContentOpacity(0)
                applyLogoTransform(progress: 1)
                logoFollowsOverlay = overlay == .home
                if !logoFollowsOverlay { setLogoOpacity(0) }
                let material: UnlitMaterial
                switch overlay {
                case .warning:
                    material = warningOverlayMaterial
                case .home:
                    material = homeOverlayMaterial ?? Self.makeOverlayMaterial(.home)
                case .loading, .handoff, .none:
                    material = Self.makeOverlayMaterial(.none)
                }
                homeUILayer.model?.materials = [
                    material
                ]
                applyOverlayOpacity(0)
            }
        }

        // Handoff visuals are handled exclusively by the two cached layers
        // above; never revive the prior loading texture beneath them.
        if overlay == .handoff {
            targetOverlayOpacity = 0
            overlayTransitionStart = nil
            return
        }

        guard overlayChanged
                || abs(targetOpacity - targetOverlayOpacity) > 0.0005 else {
            return
        }
        targetOverlayOpacity = targetOpacity
        // Unlike the effect field, the launch copy must be able to fade away
        // before the loading title appears. Overlay transitions therefore
        // interpolate in both directions.
        guard fadeDuration > 0 else {
            overlayTransitionStart = nil
            applyOverlayOpacity(targetOpacity)
            return
        }

        overlayTransitionStartOpacity = overlayOpacity
        overlayTransitionDuration = fadeDuration
        overlayTransitionStart = Date()
    }

    /// Drives the warning copy from the caller's own clock during the
    /// panel's entrance, so both fade as one. `setOverlay` takes over again
    /// from this opacity afterwards.
    func setStartupOverlayOpacity(_ opacity: Float) {
        guard currentOverlay == .warning else { return }
        overlayTransitionStart = nil
        applyOverlayOpacity(min(max(opacity, 0), 1))
    }

    private func updateEffectOpacity(at date: Date) {
        guard let transitionStart = effectTransitionStart else { return }
        let progress = min(
            1.0,
            date.timeIntervalSince(transitionStart)
                / effectTransitionDuration
        )
        applyEffectOpacity(
            effectTransitionStartOpacity
                + (targetEffectOpacity - effectTransitionStartOpacity)
                    * Float(progress)
        )
        if progress == 1.0 {
            effectTransitionStart = nil
        }
    }

    private func updateOverlayOpacity(at date: Date) {
        guard let transitionStart = overlayTransitionStart else { return }
        let progress = min(
            1.0,
            date.timeIntervalSince(transitionStart)
                / overlayTransitionDuration
        )
        applyOverlayOpacity(
            overlayTransitionStartOpacity
                + (targetOverlayOpacity - overlayTransitionStartOpacity)
                    * Float(progress)
        )
        if progress == 1.0 {
            overlayTransitionStart = nil
        }
    }

    private func updateHandoffTexture(at date: Date) {
        if let handoffToHomeStart {
            let progress = min(
                1.0,
                date.timeIntervalSince(handoffToHomeStart)
                    / Self.handoffToHomeFadeDuration
            )
            let eased = Float(progress * progress * (3 - 2 * progress))
            setHandoffContentOpacity(1 - eased)
            applyOverlayOpacity(targetOverlayOpacity)
            if progress == 1.0 {
                self.handoffToHomeStart = nil
                // From here Home fades (e.g. under the video) take the logo
                // along with the rest of the overlay.
                logoFollowsOverlay = true
                setLogoOpacity(overlayOpacity)
            }
        }
        guard currentOverlay == .handoff else { return }

        if let handoffStart {
            let elapsed = date.timeIntervalSince(handoffStart)
            let progress = min(1.0, elapsed / Self.homeHandoffDuration)
            // Ease in and out, so the ribbons emerge gently over the whole
            // logo move instead of arriving at its start.
            applyEffectOpacity(Float(progress * progress * (3 - 2 * progress)))
            applyHandoffState(progress: Float(progress))
            let contentFadeStart = Self.homeHandoffDuration
                - Self.homeContentFadeDuration
            let contentProgress = min(
                1.0,
                max(0.0, (elapsed - contentFadeStart)
                    / Self.homeContentFadeDuration)
            )
            let eased = Float(
                contentProgress * contentProgress * (3 - 2 * contentProgress)
            )
            setHandoffContentOpacity(eased)
            if progress == 1.0 {
                self.handoffStart = nil
            }
        }
    }

    private func applyEffectOpacity(_ opacity: Float) {
        guard abs(opacity - effectOpacity) > 0.0005 else { return }
        effectOpacity = opacity
        applyEffectMaterials()
    }

    private func applyEffectMaterials() {
        // Blending happens in linear light, so a linear opacity ramp looks
        // far brighter than its value early on (10% reads as about 35%).
        // Map the perceived opacity back to linear so fades look even.
        let materialOpacity = powf(effectOpacity, 2.2)
        // Material opacity is honoured in the portal world, unlike the
        // OpacityComponent on these textured planes. Keep their textures and
        // individual crossfade tints intact while scaling the whole field.
        for layer in [
            ribbonLayer,
            ribbonCrossfadeLayer,
            grainLayer,
            grainCrossfadeLayer
        ] {
            guard var material = layer.model?.materials.first as? UnlitMaterial else {
                continue
            }
            material.blending = .transparent(
                opacity: .init(floatLiteral: materialOpacity)
            )
            layer.model?.materials = [material]
        }
    }

    private func applyOverlayOpacity(_ opacity: Float) {
        overlayOpacity = opacity
        homeUILayer.components.set(OpacityComponent(opacity: opacity))
        if logoFollowsOverlay {
            setLogoOpacity(opacity)
        }
    }

    private func applyHandoffState(progress: Float) {
        applyLogoTransform(progress: Self.logoMoveEasing(progress))
        setLogoOpacity(1)
        setHandoffContentOpacity(0)
    }

    /// Places the logo between its centred loading pose (0) and its Home
    /// pose (1). `eased` is the already-eased move progress.
    private func applyLogoTransform(progress eased: Float) {
        let titleScale = 1 + (Self.homeTitleScale - 1) * eased
        let projectScale = 1 + (Self.homeProjectScale - 1) * eased
        // Both lines end with their leading edges on `homeLogoLeadingEdge`.
        let homeTitleX = Self.homeLogoLeadingEdge
            + Self.titleHalfWidth * Self.homeTitleScale
        let homeTitleY = Self.homeLogoTopEdge
            - Self.homeTitleCentreDrop * Self.homeLogoEnlargement
        let homeProjectY = Self.homeLogoTopEdge
            - Self.homeProjectCentreDrop * Self.homeLogoEnlargement
        // The centred pose floats `logoEntranceDistance` metres in front of
        // the portal and settles back onto the UI plane along the same move.
        let metresPerUnit = world.scale(relativeTo: nil).z
        let lift = logoEntranceDistance > 0 && metresPerUnit > 0
            ? logoEntranceDistance * (1 - eased)
            : 0
        let usesStage = logoEntranceDistance > 0
        let depth = (usesStage ? Self.logoStageRestDepth : Self.homeUIDepth)
            + (metresPerUnit > 0 ? lift / metresPerUnit : 0)
        let logoParent = usesStage ? logoStage : world
        for layer in [logoTitleLayer, logoProjectLayer]
        where layer.parent !== logoParent {
            layer.setParent(logoParent)
        }
        logoTitleLayer.scale = SIMD3<Float>(repeating: titleScale)
        logoTitleLayer.position = SIMD3<Float>(
            homeTitleX * eased,
            -0.019 * (1 - eased) + homeTitleY * eased,
            depth
        )
        logoProjectLayer.scale = SIMD3<Float>(repeating: projectScale)
        logoProjectLayer.position = SIMD3<Float>(
            // Offset only far enough for PROJECT's leading edge to meet the
            // leading edge of SPACE DOTS at the endpoint.
            homeTitleX * eased
                - (Self.titleHalfWidth * titleScale
                    - Self.projectHalfWidth * projectScale) * eased,
            0.110 * (1 - eased) + homeProjectY * eased,
            depth
        )
    }

    private func setLogoOpacity(_ opacity: Float) {
        logoTitleLayer.components.set(OpacityComponent(opacity: opacity))
        logoProjectLayer.components.set(OpacityComponent(opacity: opacity))
    }

    private func setHandoffContentOpacity(_ opacity: Float) {
        handoffContentLayer.components.set(OpacityComponent(opacity: opacity))
    }

    /// Cubic Bézier (0.5, 0, 0.45, 1): the logo gradually gathers speed
    /// and settles with a long, gentle tail instead of braking. Over the
    /// full move duration its top speed stays below the old smoothstep's.
    private static func logoMoveEasing(_ t: Float) -> Float {
        let x1: Float = 0.5
        let x2: Float = 0.45
        guard t > 0 else { return 0 }
        guard t < 1 else { return 1 }
        // x(s) is monotonic for these control points; bisect for s.
        var lower: Float = 0
        var upper: Float = 1
        var s = t
        for _ in 0..<24 {
            let inverse = 1 - s
            let x = 3 * inverse * inverse * s * x1
                + 3 * inverse * s * s * x2
                + s * s * s
            if x < t { lower = s } else { upper = s }
            s = (lower + upper) / 2
        }
        // With y1 = 0 and y2 = 1, y(s) reduces to smoothstep in s.
        return s * s * (3 - 2 * s)
    }

    func fitPortal(to bounds: BoundingBox) {
        // Keep portal and world registered to exactly the same front plane.
        // Their shared scale preserves the actual depth behind that mask.
        let horizontalScale = bounds.extents.x / Self.basePlaneWidth
        let verticalScale = bounds.extents.y / Self.basePlaneHeight
        let depthScale = min(horizontalScale, verticalScale)

        let scale = SIMD3<Float>(
            horizontalScale,
            verticalScale,
            depthScale
        )
        let position = SIMD3<Float>(
            bounds.center.x,
            bounds.center.y,
            bounds.min.z + 0.012
        )
        portalSurface.scale = scale
        portalSurface.position = position
        world.scale = scale
        world.position = position
        logoStage.scale = scale
        logoStage.position = position
    }

    private static func makeRoundedPortalMesh() -> MeshResource {
        let halfWidth = basePlaneWidth / 2
        let halfHeight = basePlaneHeight / 2
        let radius = min(portalCornerRadius, halfWidth, halfHeight)
        let segmentsPerCorner = 8
        let cornerCenters: [SIMD2<Float>] = [
            SIMD2<Float>(halfWidth - radius, -halfHeight + radius),
            SIMD2<Float>(halfWidth - radius, halfHeight - radius),
            SIMD2<Float>(-halfWidth + radius, halfHeight - radius),
            SIMD2<Float>(-halfWidth + radius, -halfHeight + radius)
        ]
        let startAngles: [Float] = [
            -.pi / 2,
            0,
            .pi / 2,
            .pi
        ]

        var positions: [SIMD3<Float>] = [SIMD3<Float>(0, 0, 0)]
        for (cornerIndex, center) in cornerCenters.enumerated() {
            for segment in 0..<segmentsPerCorner {
                let progress = Float(segment) / Float(segmentsPerCorner)
                let angle = startAngles[cornerIndex] + progress * .pi / 2
                positions.append(
                    SIMD3<Float>(
                        center.x + cos(angle) * radius,
                        center.y + sin(angle) * radius,
                        0
                    )
                )
            }
        }

        let boundaryVertexCount = positions.count - 1
        var indices: [UInt32] = []
        indices.reserveCapacity(boundaryVertexCount * 3)
        for boundaryIndex in 0..<boundaryVertexCount {
            let current = UInt32(boundaryIndex + 1)
            let next = UInt32(
                boundaryIndex + 1 == boundaryVertexCount
                    ? 1
                    : boundaryIndex + 2
            )
            indices.append(contentsOf: [0, current, next])
        }

        var descriptor = MeshDescriptor(name: "Rounded portal opening")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try! MeshResource.generate(from: [descriptor])
    }

    func startRibbonAnimation() {
        guard animationTimer == nil else { return }

        // The timer runs the lightweight opacity interpolation at 30 fps. A
        // new expensive bitmap is generated only twice per second, while the
        // longer crossfade keeps the perceived motion continuous.
        animationTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / Self.animationTickRate,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateRibbonTexture(at: Date())
            }
        }
        updateRibbonTexture(at: Date())
    }

    func prewarmOverlayMaterials() {
        if homeOverlayMaterial == nil {
            homeOverlayMaterial = Self.makeOverlayMaterial(.home)
        }
    }

    private func updateRibbonTexture(at date: Date) {
        advanceEffectAnimation(at: date)
        updateEffectOpacity(at: date)
        updateOverlayOpacity(at: date)
        updateHandoffTexture(at: date)
        guard effectOpacity > 0.0005 else { return }
        // Keep the blurred backdrop as one stable field while the foreground
        // title crosses the portal. Resuming the ribbon crossfade after this
        // brief handoff avoids a visible dim/bright double-image.
        guard currentOverlay != .loading, currentOverlay != .handoff else {
            // Only the ribbons hold still. The grain keeps running while it
            // fades in, so it is already alive when the logo arrives.
            updateGrain(at: date.timeIntervalSince(grainClockStart))
            applyEffectMaterials()
            return
        }
        let realElapsed = effectAnimationElapsed
        let elapsed = realElapsed * Self.ribbonMotionRate
        let frame = Int(realElapsed * Self.textureRefreshRate)
        if frame != lastTextureFrame {
            lastTextureFrame = frame
            incomingTexture = Self.makeRibbonTexture(elapsed: elapsed)
            crossfadeStart = date
        }

        if let incomingTexture, let crossfadeStart {
            let progress = min(
                1.0,
                date.timeIntervalSince(crossfadeStart)
                    / Self.crossfadeDuration
            )
            ribbonCrossfadeLayer.model?.materials = [
                Self.makeRibbonMaterial(
                    texture: incomingTexture,
                    opacity: Float(progress)
                )
            ]

            if progress == 1.0 {
                ribbonLayer.model?.materials = [
                    Self.makeRibbonMaterial(texture: incomingTexture)
                ]
                self.incomingTexture = nil
                self.crossfadeStart = nil
                ribbonCrossfadeLayer.model?.materials = [
                    Self.makeRibbonMaterial(texture: nil, opacity: 0)
                ]
            }
        }

        // A very small overall drift reinforces the depth without replacing
        // the actual per-ribbon wave motion in the generated texture.
        let ribbonPosition = SIMD3<Float>(
            sin(Float(realElapsed * 0.32)) * 0.015,
            sin(Float(realElapsed * 0.45)) * 0.010,
            Self.ribbonDepth
        )
        ribbonLayer.position = ribbonPosition
        ribbonCrossfadeLayer.position = SIMD3<Float>(
            ribbonPosition.x,
            ribbonPosition.y,
            Self.ribbonDepth + 0.0001
        )

        updateGrain(at: date.timeIntervalSince(grainClockStart))
        if effectOpacity < 0.999 {
            applyEffectMaterials()
        }
    }

    private func setEffectAnimationPaused(_ paused: Bool) {
        guard paused != effectAnimationIsPaused else { return }
        let now = Date()
        if paused {
            advanceEffectAnimation(at: now)
        } else {
            effectAnimationLastTick = now
        }
        effectAnimationIsPaused = paused
    }

    private func advanceEffectAnimation(at date: Date) {
        defer { effectAnimationLastTick = date }
        guard !effectAnimationIsPaused else { return }
        effectAnimationElapsed += max(
            0,
            date.timeIntervalSince(effectAnimationLastTick)
        )
    }

    private func freezeEffectFrames() {
        if let incomingTexture {
            ribbonLayer.model?.materials = [
                Self.makeRibbonMaterial(texture: incomingTexture)
            ]
        }
        incomingTexture = nil
        crossfadeStart = nil
        ribbonCrossfadeLayer.model?.materials = [
            Self.makeRibbonMaterial(texture: nil, opacity: 0)
        ]
        grainCrossfadeLayer.model?.materials = [
            Self.makeGrainMaterial(texture: nil, opacity: 0)
        ]
        applyEffectMaterials()
    }

    private func updateGrain(at elapsed: Double) {
        guard !grainTextures.isEmpty else { return }

        let progress = elapsed * Self.grainFrameRate
        let lowerFrame = Int(progress.rounded(.down))
            % Self.grainFrameCount
        let upperFrame = (lowerFrame + 1) % Self.grainFrameCount
        let crossfade = Float(progress - progress.rounded(.down))

        if lowerFrame != lastGrainFrame {
            lastGrainFrame = lowerFrame
            grainLayer.model?.materials = [
                Self.makeGrainMaterial(texture: grainTextures[lowerFrame])
            ]
        }

        grainCrossfadeLayer.model?.materials = [
            Self.makeGrainMaterial(
                texture: grainTextures[upperFrame],
                opacity: crossfade
            )
        ]
    }

    private static func makeRibbonMaterial(
        texture: TextureResource?,
        opacity: Float = 1
    ) -> UnlitMaterial {
        var material = UnlitMaterial()
        material.color = .init(
            tint: UIColor(white: 1, alpha: CGFloat(opacity)),
            texture: texture.map { .init($0) }
        )
        material.blending = .transparent(opacity: 1.0)
        material.faceCulling = .none
        material.readsDepth = false
        material.writesDepth = false
        return material
    }

    private static func makePortalBlackMaterial() -> UnlitMaterial {
        var material = UnlitMaterial(color: .black)
        material.readsDepth = false
        material.writesDepth = false
        return material
    }

    private static func makeGrainMaterial(
        texture: TextureResource?,
        opacity: Float = 1
    ) -> UnlitMaterial {
        var material = UnlitMaterial()
        material.color = .init(
            tint: UIColor(white: 1, alpha: CGFloat(opacity)),
            texture: texture.map { .init($0) }
        )
        material.blending = .transparent(opacity: 1.0)
        material.readsDepth = false
        material.writesDepth = false
        return material
    }

    private static func makeGrainTexture(frame: Double) -> TextureResource? {
        let renderer = ImageRenderer(
            content: PortalFilmGrainOverlay(frame: frame)
                .frame(width: textureSize.width, height: textureSize.height)
        )
        renderer.scale = 1.0

        guard let image = renderer.cgImage else { return nil }
        return try? TextureResource(
            image: image,
            withName: "Portal Film Grain Frame \(Int(frame))",
            options: .init(semantic: .color)
        )
    }

    private static func makeOverlayMaterial(
        _ overlay: AstrophagePortalOverlay
    ) -> UnlitMaterial {
        let overlayView: AnyView
        let textureName: String
        switch overlay {
        case .warning:
            overlayView = AnyView(PortalWarningOverlay())
            textureName = "Portal warning overlay"
        case .home:
            overlayView = AnyView(PortalHomeFinalStateOverlay())
            textureName = "Portal home overlay"
        case .loading, .handoff, .none:
            // Loading and handoff consist only of the persistent logo
            // layers, so the overlay plane itself stays clear.
            var material = UnlitMaterial(color: .clear)
            material.blending = .transparent(opacity: 1.0)
            material.readsDepth = false
            material.writesDepth = false
            return material
        }

        return makePortalTextureMaterial(
            content: overlayView,
            textureName: textureName,
            renderScale: overlay == .home ? 2.0 : 1.0
        )
    }

    /// A layer entity with one logo line's vector text mesh as a child. Like
    /// the textures, the mesh is laid out in points and mapped onto the
    /// portal plane, centred at the layer's origin.
    private static func makeLogoLayer(
        _ line: PortalLogoLine,
        sortOrder: Int32,
        brightness: CGFloat = 1
    ) -> ModelEntity {
        let layer = ModelEntity()
        layer.name = "Portal logo \(line.text)"
        layer.position.z = homeUIDepth
        layer.components.set(OpacityComponent(opacity: 0))

        var string = AttributedString(line.text)
        string.uiKit.font = UIFont.systemFont(
            ofSize: line.fontSize,
            weight: line.uiFontWeight
        )
        string.uiKit.kern = line.tracking
        var extrusion = MeshResource.ShapeExtrusionOptions()
        extrusion.extrusionMethod = .linear(depth: 0.5)
        extrusion.boundaryResolution = .uniformSegmentsPerSpan(segmentCount: 16)
        guard let mesh = try? MeshResource(
            extruding: string,
            extrusionOptions: extrusion
        ) else {
            return layer
        }

        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(line.color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        var material = UnlitMaterial(color: UIColor(
            red: red * brightness,
            green: green * brightness,
            blue: blue * brightness,
            alpha: alpha
        ))
        material.blending = .transparent(opacity: 1.0)
        material.faceCulling = .none
        material.readsDepth = false
        material.writesDepth = false

        let text = ModelEntity(mesh: mesh, materials: [material])
        text.name = "Portal logo text \(line.text)"
        // `MeshResource(extruding:)` lays text out at one unit per inch
        // (72 points), so scale it up to points before mapping onto the plane.
        let pointsPerMeshUnit: Float = 72
        let pointScale = pointsPerMeshUnit * SIMD3<Float>(
            basePlaneWidth / Float(portalUISize.width),
            basePlaneHeight / Float(portalUISize.height),
            basePlaneWidth / Float(portalUISize.width)
        )
        let center = mesh.bounds.center
        text.scale = pointScale
        text.position = SIMD3<Float>(
            -center.x * pointScale.x,
            -center.y * pointScale.y,
            -center.z * pointScale.z + logoTextLift
        )
        text.components.set(
            ModelSortGroupComponent(group: portalSortGroup, order: sortOrder)
        )
        layer.addChild(text)
        return layer
    }

    private static func makeHandoffContentMaterial() -> UnlitMaterial {
        makePortalTextureMaterial(
            content: AnyView(PortalHandoffContentOverlay()),
            textureName: "Portal handoff Home content",
            renderScale: 2.0
        )
    }

    private static func makePortalTextureMaterial(
        content: AnyView,
        textureName: String,
        renderScale: CGFloat = 1.0
    ) -> UnlitMaterial {
        let renderer = ImageRenderer(
            content: content
                .frame(
                    width: portalUISize.width,
                    height: portalUISize.height
                )
        )
        renderer.scale = renderScale

        let texture: TextureResource?
        if let image = renderer.cgImage {
            texture = try? TextureResource(
                image: image,
                withName: textureName,
                options: .init(semantic: .color)
            )
        } else {
            texture = nil
        }

        var material = UnlitMaterial()
        material.color = .init(
            tint: .white,
            texture: texture.map { .init($0) }
        )
        material.blending = .transparent(opacity: 1.0)
        // The title/project meshes are viewed obliquely through the portal.
        // Keep both faces renderable so the logo cannot vanish when the user
        // looks from the right side of the panel.
        material.faceCulling = .none
        material.readsDepth = false
        material.writesDepth = false
        return material
    }

    private static func makeRibbonTexture(elapsed: Double) -> TextureResource? {
        let renderer = ImageRenderer(
            content: ZStack {
                Color.black
                AstrophageRibbonView(
                    rendersAsynchronously: false,
                    showsFilmGrain: false,
                    elapsedOverride: elapsed
                )
                .scaleEffect(Self.portalPatternScale)
            }
            .frame(width: textureSize.width, height: textureSize.height)
            .clipped()
        )
        renderer.scale = 1.0

        guard let image = renderer.cgImage else { return nil }
        return try? TextureResource(
            image: image,
            withName: "Astrophage Ribbon Frame \(Int(elapsed * 1_000))",
            options: .init(semantic: .color)
        )
    }

}

#Preview("Astrophage portal — masked panel") {
    AstrophageRibbonPortalView()
        .frame(width: 1_280, height: 720)
        .background(.black)
}
