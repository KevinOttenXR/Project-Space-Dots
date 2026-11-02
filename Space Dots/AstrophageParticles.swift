import CoreGraphics
import RealityKit
import UIKit

@MainActor
final class AstrophageParticles: Entity {

    static let retirementDuration: Float = 8.5

    private static let sharedBokehParticleTexture = makeSoftParticleTexture()
    private static let sharedStarParticleTexture = makeStarParticleTexture()
    private static let sharedOvalFogTexture = makeOvalFogTexture()

    private var wasVisible = false
    private var wasPlaying = false
    private var isRetired = false
    private var isRecenterGeneration = false
    private var isPrewarmingWhileHidden = false
    private var lastOpacity: Float = -1.0
    private var rootOpacity: Float = 0.0
    private var rootFadeStartOpacity: Float = 0.0
    private var rootFadeElapsed: Float = 0.0
    private let rootFadeDuration: Float = 1.15
    private var rootFadeIsActive = false
    private var ovalFog: Entity?
    private var ovalFadeElapsed: Float = 0.0
    private var ovalFadeDuration: Float = 2.0
    private var ovalFadeStartOpacity: Float = 0.0
    private var ovalCurrentOpacity: Float = 0.0
    private var ovalFadeTargetOpacity: Float = 0.0
    // Keep the oval at 80% of its previous maximum opacity (0.50 -> 0.40).
    private let ovalTargetOpacity: Float = 0.40
    /// The oval's distance from the viewer with the particles 2.5 m ahead.
    private let ovalUsualViewerDistance: Float = 7.0
    private var recenterEmissionFadeElapsed: Float = 0.0
    private let recenterEmissionFadeDuration: Float = 1.4
    private var recenterEmissionFadeIsActive = false
    private var emitterBirthTargets: [ObjectIdentifier: (rate: Float, variation: Float)] = [:]
    private var swarmClusters: [Entity] = []
    private var swarmTime: Float = 0
    private var swarmUpdateElapsed: Float = 0
    private let swarmMovement: Float = 0.80
    private let swarmEvolution: Float = 0.85

    private let roomCloudWidth: Float = 2.0
    private let roomCloudHeight: Float = 2.5

    private let backgroundParticleCount: Float = 24000.0
    private let foregroundParticleCount: Float = 800.0
    private let backgroundLifespan: Double = 7.5
    private let foregroundLifespan: Double = 4.45

    required init() {
        super.init()
        name = "Astrophage Particles"
        components.set(OpacityComponent(opacity: 0.0))

        let bokehParticleTexture = Self.sharedBokehParticleTexture
        let starParticleTexture = Self.sharedStarParticleTexture
        addChild(makeBackgroundEmitter(
            texture: starParticleTexture,
            position: [0.0, 0.0, 0.0],
            shapeSize: [roomCloudWidth, roomCloudHeight, 0.12],
            name: "Room"
        ))
        let bokehZ: Float = 1.5

        addChild(makeForegroundEmitter(
            texture: bokehParticleTexture,
            position: [0.0, -0.5, bokehZ],
            shapeSize: [roomCloudWidth, roomCloudHeight * 0.78, 0.12],
            particleCount: foregroundParticleCount,
            name: "Room"
        ))
        if let ovalFog = makeOvalFog() {
            self.ovalFog = ovalFog
            addChild(ovalFog)
        }
        configureSpatialDistribution()
        configureSwarm()
    }

    private func configureSpatialDistribution() {
        guard let background = children.first(where: { $0.name == "Astrophage Distant Points Room" }),
              var emitter = background.components[ParticleEmitterComponent.self],
              let foreground = children.first(where: { $0.name == "Astrophage Foreground Bokeh Room" }),
              var bokeh = foreground.components[ParticleEmitterComponent.self] else { return }
        emitter.emitterShapeSize.z = 0.8
        background.position.z = -0.34
        emitter.mainEmitter.birthRate *= 0.75
        emitter.mainEmitter.size = 0.009
        emitter.mainEmitter.sizeVariation = 0.007
        background.components.set(emitter)

        let cluster = makeBackgroundEmitter(
            texture: Self.sharedStarParticleTexture,
            position: [0.35, 0.2, -0.35],
            shapeSize: [0.8, 1.1, 0.8],
            name: "Cluster"
        )
        if var clusterEmitter = cluster.components[ParticleEmitterComponent.self] {
            clusterEmitter.mainEmitter.birthRate *= 0.25
            assert(abs(emitter.mainEmitter.birthRate + clusterEmitter.mainEmitter.birthRate
                       - backgroundParticleCount / Float(backgroundLifespan)) < 0.01)
            clusterEmitter.mainEmitter.size = 0.009
            clusterEmitter.mainEmitter.sizeVariation = 0.007
            cluster.components.set(clusterEmitter)
        }
        addChild(cluster)
        bokeh.emitterShapeSize.z = 0.5
        foreground.position.z = 1.31
        bokeh.mainEmitter.size = 0.025
        bokeh.mainEmitter.sizeVariation = 0.015
        foreground.components.set(bokeh)
        rememberEmitterBirthTargets()
    }
    private func configureSwarm() {
        guard let first = children.first(where: { $0.name == "Astrophage Distant Points Cluster" }),
              var emitter = first.components[ParticleEmitterComponent.self] else { return }
        emitter.mainEmitter.birthRate *= 0.5
        emitter.mainEmitter.birthRateVariation *= 0.5
        emitter.mainEmitter.noiseStrength = 0.012
        emitter.particlesInheritTransform = true
        if var sequence = emitter.mainEmitter.imageSequence {
            sequence.frameRate = 1.5
            sequence.frameRateVariation = 0.9
            emitter.mainEmitter.imageSequence = sequence
        }
        first.components.set(emitter)
        let second = Entity()
        second.name = "Astrophage Distant Points Cluster 2"
        second.components.set(emitter)
        addChild(second)
        swarmClusters = [first, second]
        rememberEmitterBirthTargets()
        updateSwarm()
        assert(swarmClusters.count == 2 && abs(emitter.mainEmitter.birthRate * 2 - 800) < 0.01)
    }

    private func updateSwarm(updateShape: Bool = true) {
        for (index, cluster) in swarmClusters.enumerated() {
            let phase: Float = index == 0 ? 0 : 2.1
            let speed: Float = index == 0 ? 1 : 0.79
            cluster.position = [
                (index == 0 ? 0.08 : 0.62) + swarmMovement * 0.45 * sin(swarmTime * 0.13 * speed + phase),
                0.20 + swarmMovement * 0.25 * sin(swarmTime * 0.10 * speed + phase * 1.4),
                -0.35 + swarmMovement * 0.20 * sin(swarmTime * 0.08 * speed + phase * 0.7)
            ]
            guard updateShape else { continue }
            guard var emitter = cluster.components[ParticleEmitterComponent.self] else { continue }
            let size = 1 + swarmEvolution * 0.45 * sin(swarmTime * 0.12 * speed + phase)
            emitter.emitterShapeSize = [0.8 * size, 1.1 * size, 0.8 * size]
            assert(size >= 0.55 && size <= 1.45)
            cluster.components.set(emitter)
        }
    }

    func updatePlayback(isVisible: Bool, isPlaying: Bool, opacity: Double) {
        updateOpacity(opacity)

        guard isVisible != wasVisible || isPlaying != wasPlaying else { return }

        if isRetired {
            updateRetiredPlayback(isVisible: isVisible, isPlaying: isPlaying)
            return
        }

        let isRevealingPrewarmedGeneration = isVisible
            && !wasVisible
            && isPrewarmingWhileHidden

        if isVisible && !wasVisible {
            if isRevealingPrewarmedGeneration {
                isPrewarmingWhileHidden = false
                isRecenterGeneration = false
                recenterEmissionFadeIsActive = false
                setEmissionScale(1.0)
                setOvalImmediately(ovalTargetOpacity)
            } else if isRecenterGeneration {
                recenterEmissionFadeIsActive = true
                beginOvalFadeIn(duration: 1.4)
            } else {
                beginOvalFadeIn()
            }
        } else if !isVisible && !isPrewarmingWhileHidden {
            setEmissionScale(0.0)
            beginOvalFade(to: 0.0, duration: rootFadeDuration)
        }

        for child in children {
            guard var emitter = child.components[ParticleEmitterComponent.self] else { continue }

            if !isVisible {
                emitter.simulationState = .play
            } else if !wasVisible
                        && !isRecenterGeneration
                        && !isRevealingPrewarmedGeneration {
                setEmissionScale(1.0)
                restart(&emitter, for: child, isPlaying: isPlaying)
            } else {
                emitter.simulationState = isPlaying ? .play : .pause
            }

            child.components.set(emitter)
        }

        wasVisible = isVisible
        wasPlaying = isPlaying
    }

    func beginAfterRecenter(isVisible: Bool, isPlaying: Bool, opacity: Double) {
        updateOpacity(opacity)
        isRetired = false
        isRecenterGeneration = true
        recenterEmissionFadeElapsed = 0.0
        isPrewarmingWhileHidden = !isVisible
        recenterEmissionFadeIsActive = isVisible

        if isVisible {
            setEmissionScale(0.0)
            beginOvalFadeIn(duration: 1.4)
        } else {
            setEmissionScale(1.0)
            setOvalImmediately(ovalTargetOpacity)
        }

        for child in children {
            guard var emitter = child.components[ParticleEmitterComponent.self] else { continue }
            emitter.simulationState = isVisible
                ? (isPlaying ? .play : .pause)
                : .play
            child.components.set(emitter)
        }

        wasVisible = isVisible
        wasPlaying = isPlaying
    }

    func retireAfterRecenter(isVisible: Bool, isPlaying: Bool, opacity: Double) {
        updateOpacity(opacity)
        isRetired = true
        isRecenterGeneration = false
        isPrewarmingWhileHidden = false
        recenterEmissionFadeIsActive = false
        setEmissionScale(0.0)
        beginOvalFade(to: 0.0, duration: 1.0)
        updateRetiredPlayback(isVisible: isVisible, isPlaying: isPlaying)
    }

    func update(deltaTime: Float) {
        if wasVisible && wasPlaying && !isRetired {
            swarmTime += deltaTime
            swarmUpdateElapsed += deltaTime
            let updateShape = swarmUpdateElapsed >= 0.1
            updateSwarm(updateShape: updateShape)
            if updateShape { swarmUpdateElapsed = 0 }
        }
        if ovalFadeElapsed < ovalFadeDuration, ovalFog != nil {
            ovalFadeElapsed = min(ovalFadeDuration, ovalFadeElapsed + deltaTime)
            let progress = ovalFadeElapsed / max(ovalFadeDuration, 0.001)
            let eased = smoothstep(progress)
            setOvalOpacity(
                ovalFadeStartOpacity
                    + ((ovalFadeTargetOpacity - ovalFadeStartOpacity) * eased)
            )
        }

        if rootFadeIsActive {
            rootFadeElapsed = min(rootFadeDuration, rootFadeElapsed + deltaTime)
            let progress = smoothstep(rootFadeElapsed / rootFadeDuration)
            setRootOpacity(
                rootFadeStartOpacity * (1.0 - progress)
            )
            if rootFadeElapsed >= rootFadeDuration {
                rootFadeIsActive = false
                setRootOpacity(0.0)
                setEmissionScale(0.0)
                stopEmitters()
                setOvalImmediately(0.0)
            }
        }

        guard recenterEmissionFadeIsActive,
              wasVisible,
              wasPlaying,
              !isRetired else { return }
        recenterEmissionFadeElapsed = min(
            recenterEmissionFadeDuration,
            recenterEmissionFadeElapsed + deltaTime
        )
        let progress = recenterEmissionFadeElapsed / recenterEmissionFadeDuration
        setEmissionScale(smoothstep(progress))
        if recenterEmissionFadeElapsed >= recenterEmissionFadeDuration {
            recenterEmissionFadeIsActive = false
            isRecenterGeneration = false
        }
    }

    /// How far from the viewer the oval hangs for a wanted distance. It
    /// never comes closer than its usual 7 m.
    func ovalViewerDistance(for wantedDistance: Float) -> Float {
        max(wantedDistance, ovalUsualViewerDistance)
    }

    /// Puts the oval at `position`, `viewerDistance` from the viewer. It
    /// grows with distance so it keeps looking the same size; `growth`
    /// makes it look that many times bigger, for a screen that looks bigger.
    func placeOval(
        at position: SIMD3<Float>,
        relativeTo referenceEntity: Entity?,
        viewerDistance: Float,
        growth: Float = 1.0
    ) {
        guard let ovalFog else { return }
        ovalFog.setPosition(position, relativeTo: referenceEntity)
        ovalFog.scale = SIMD3<Float>(
            repeating: (viewerDistance / ovalUsualViewerDistance) * max(growth, 1.0)
        )
    }

    var isFullyFadedOut: Bool {
        rootOpacity <= 0.0001 && !rootFadeIsActive
    }

    private func beginOvalFadeIn(duration: Float = 2.0) {
        beginOvalFade(to: ovalTargetOpacity, duration: duration)
    }

    private func beginOvalFade(to targetOpacity: Float, duration: Float) {
        ovalFadeStartOpacity = ovalCurrentOpacity
        ovalFadeTargetOpacity = targetOpacity
        ovalFadeDuration = duration
        ovalFadeElapsed = 0.0
    }

    private func setOvalOpacity(_ opacity: Float) {
        ovalCurrentOpacity = opacity
        ovalFog?.components.set(OpacityComponent(opacity: opacity))
    }

    private func setOvalImmediately(_ opacity: Float) {
        ovalFadeStartOpacity = opacity
        ovalFadeTargetOpacity = opacity
        ovalFadeElapsed = ovalFadeDuration
        setOvalOpacity(opacity)
    }

    private func smoothstep(_ value: Float) -> Float {
        let clamped = min(max(value, 0.0), 1.0)
        return clamped * clamped * (3.0 - (2.0 * clamped))
    }

    private func updateOpacity(_ opacity: Double) {
        let clampedOpacity = Float(min(max(opacity, 0.0), 1.0))
        if clampedOpacity <= 0.0001 {
            if rootOpacity > 0.0001, !rootFadeIsActive {
                rootFadeStartOpacity = rootOpacity
                rootFadeElapsed = 0.0
                rootFadeIsActive = true
            }
            lastOpacity = clampedOpacity
            return
        }

        rootFadeIsActive = false
        rootFadeElapsed = 0.0
        if abs(clampedOpacity - rootOpacity) > 0.0001
                || abs(clampedOpacity - lastOpacity) > 0.0001 {
            setRootOpacity(clampedOpacity)
            lastOpacity = clampedOpacity
        }
    }

    private func setRootOpacity(_ opacity: Float) {
        rootOpacity = min(max(opacity, 0.0), 1.0)
        components.set(OpacityComponent(opacity: rootOpacity))
    }

    private func stopEmitters() {
        for child in children {
            guard var emitter = child.components[ParticleEmitterComponent.self] else {
                continue
            }
            emitter.simulationState = .stop
            child.components.set(emitter)
        }
    }

    private func rememberEmitterBirthTargets() {
        for child in children {
            guard let emitter = child.components[ParticleEmitterComponent.self] else {
                continue
            }
            emitterBirthTargets[ObjectIdentifier(child)] = (
                emitter.mainEmitter.birthRate,
                emitter.mainEmitter.birthRateVariation
            )
        }
    }

    private func setEmissionScale(_ scale: Float) {
        let clampedScale = min(max(scale, 0.0), 1.0)
        for child in children {
            guard let target = emitterBirthTargets[ObjectIdentifier(child)],
                  var emitter = child.components[ParticleEmitterComponent.self] else {
                continue
            }
            var particles = emitter.mainEmitter
            particles.birthRate = target.rate * clampedScale
            particles.birthRateVariation = target.variation * clampedScale
            emitter.mainEmitter = particles
            child.components.set(emitter)
        }
    }

    private func updateRetiredPlayback(isVisible: Bool, isPlaying: Bool) {
        for child in children {
            guard var emitter = child.components[ParticleEmitterComponent.self] else {
                continue
            }
            emitter.simulationState = isVisible
                ? (isPlaying ? .play : .pause)
                : .play
            child.components.set(emitter)
        }
        if !isVisible {
            beginOvalFade(to: 0.0, duration: rootFadeDuration)
        }
        wasVisible = isVisible
        wasPlaying = isPlaying
    }

    private func restart(
        _ emitter: inout ParticleEmitterComponent,
        for child: Entity,
        isPlaying: Bool
    ) {
        emitter.restart()
        let isDistantPoints = child.name.contains("Distant Points")
        let isBokeh = child.name.contains("Foreground Bokeh")
        let distantBurst = child.name.contains("Cluster") ? 625 : (emitter.mainEmitter.birthRate < 1000 ? 1250 : 3750)
        emitter.burstCount = isDistantPoints ? distantBurst : (isBokeh ? 320 : 0)
        emitter.burstCountVariation = isDistantPoints ? 350 : (isBokeh ? 35 : 0)
        emitter.burst()
        emitter.simulationState = isPlaying ? .play : .pause
    }

    private func makeBackgroundEmitter(
        texture: TextureResource?,
        position: SIMD3<Float>,
        shapeSize: SIMD3<Float>,
        name: String
    ) -> Entity {
        let entity = Entity()
        entity.name = "Astrophage Distant Points \(name)"
        entity.position = position

        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .box
        emitter.birthLocation = .volume
        emitter.birthDirection = .local
        emitter.emitterShapeSize = shapeSize
        emitter.emissionDirection = [0.0, 0.0, 1.0]
        emitter.speed = 0.30
        emitter.speedVariation = 0.05
        emitter.spawnSpreadFactor = 0.025
        emitter.spawnSpreadFactorVariation = 0.04
        emitter.particlesInheritTransform = false

        var particles = emitter.mainEmitter
        particles.birthRate = backgroundParticleCount / Float(backgroundLifespan)
        particles.birthRateVariation = 7.0
        particles.size = 0.0105
        particles.sizeVariation = 0.0055
        particles.billboardMode = .free(axis: [0.0, 1.0, 0.0], variation: 0.85)
        particles.angle = 0.0
        particles.angleVariation = .pi
        particles.angularSpeed = 1.4
        particles.angularSpeedVariation = 2.2
        particles.lifeSpan = backgroundLifespan
        particles.lifeSpanVariation = 0.75
        particles.opacityCurve = .constant
        particles.sizeMultiplierAtEndOfLifespan = 1.35
        particles.sizeMultiplierAtEndOfLifespanPower = 18.0
        particles.noiseStrength = 0.008
        particles.noiseScale = 0.8
        particles.noiseAnimationSpeed = 0.3
        particles.isLightingEnabled = false
        particles.blendMode = .additive
        particles.image = texture
        var imageSequence = ParticleEmitterComponent.ParticleEmitter.ImageSequence()
        imageSequence.rowCount = 1
        imageSequence.columnCount = 8
        imageSequence.initialFrameVariation = 7
        imageSequence.frameRate = 4.0
        imageSequence.frameRateVariation = 4.5
        imageSequence.animationMode = .autoReverse
        particles.imageSequence = imageSequence
        particles.color = .evolving(
            start: .random(
                a: UIColor(red: 1.0, green: 0.08, blue: 0.16, alpha: 0.80),
                b: UIColor(red: 1.0, green: 0.42, blue: 0.52, alpha: 1.0)
            ),
            end: .random(
                a: UIColor(white: 1.0, alpha: 1.0),
                b: UIColor(white: 1.0, alpha: 1.0)
            )
        )
        particles.colorEvolutionPower = 3.0
        emitter.mainEmitter = particles
        emitter.simulationState = .stop
        entity.components.set(emitter)
        return entity
    }

    private func makeOvalFog() -> Entity? {
        guard let texture = Self.sharedOvalFogTexture else { return nil }

        var material = UnlitMaterial()
        material.color = .init(
            tint: UIColor(red: 0.64, green: 0.008, blue: 0.11, alpha: 1.0),
            texture: .init(texture)
        )
        material.blending = .transparent(opacity: 1.0)
        material.readsDepth = true
        material.writesDepth = false

        let oval = ModelEntity(
            mesh: .generatePlane(width: 11.0, height: 6.2),
            materials: [material]
        )
        oval.name = "Astrophage Feathered Oval Fog"
        oval.position = SIMD3<Float>(x: 0.0, y: -0.50, z: -4.50)
        var billboard = BillboardComponent()
        billboard.blendFactor = 1.0
        oval.components.set(billboard)
        oval.components.set(OpacityComponent(opacity: 0.0))
        oval.components.set(GroundingShadowComponent(castsShadow: false))
        return oval
    }

    private func makeForegroundEmitter(
        texture: TextureResource?,
        position: SIMD3<Float>,
        shapeSize: SIMD3<Float>,
        particleCount: Float,
        name: String
    ) -> Entity {
        let entity = Entity()
        entity.name = "Astrophage Foreground Bokeh \(name)"
        entity.position = position

        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .box
        emitter.birthLocation = .volume
        emitter.birthDirection = .local
        emitter.emitterShapeSize = shapeSize
        emitter.emissionDirection = [0.0, 0.0, 1.0]
        emitter.speed = 0.45
        emitter.speedVariation = 0.05
        emitter.spawnSpreadFactor = 0.035
        emitter.spawnSpreadFactorVariation = 0.04
        emitter.particlesInheritTransform = false

        var particles = emitter.mainEmitter
        particles.birthRate = particleCount / Float(foregroundLifespan)
        particles.birthRateVariation = 3.0
        particles.size = 0.035
        particles.sizeVariation = 0.020
        particles.lifeSpan = foregroundLifespan
        particles.lifeSpanVariation = 0.25
        particles.opacityCurve = .constant
        particles.sizeMultiplierAtEndOfLifespan = 1.45
        particles.sizeMultiplierAtEndOfLifespanPower = 18.0
        particles.noiseStrength = 0.01
        particles.noiseScale = 0.65
        particles.noiseAnimationSpeed = 0.25
        particles.isLightingEnabled = false
        particles.blendMode = .additive
        particles.image = texture
        particles.color = .evolving(
            start: .random(
                a: UIColor(red: 1.0, green: 0.10, blue: 0.18, alpha: 0.34),
                b: UIColor(red: 1.0, green: 0.48, blue: 0.58, alpha: 0.78)
            ),
            end: .random(
                a: UIColor(white: 1.0, alpha: 1.0),
                b: UIColor(white: 1.0, alpha: 1.0)
            )
        )
        particles.colorEvolutionPower = 3.0
        emitter.mainEmitter = particles
        emitter.simulationState = .stop
        entity.components.set(emitter)
        return entity
    }

    private static func makeSoftParticleTexture() -> TextureResource? {
        let size = 64
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        let colors = [
            UIColor.white.cgColor,
            UIColor.white.withAlphaComponent(0.70).cgColor,
            UIColor.white.withAlphaComponent(0.24).cgColor,
            UIColor.clear.cgColor
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: colors,
            locations: [0.0, 0.30, 0.64, 1.0]
        ) else {
            return nil
        }

        let center = CGPoint(x: CGFloat(size) / 2.0, y: CGFloat(size) / 2.0)
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0.0,
            endCenter: center,
            endRadius: CGFloat(size) / 2.0,
            options: []
        )

        guard let image = context.makeImage() else { return nil }
        return try? TextureResource(
            image: image,
            withName: "Astrophage Soft Bokeh",
            options: .init(semantic: .color)
        )
    }

    private static func makeOvalFogTexture() -> TextureResource? {
        let width = 2048
        let height = 1024
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)

        let colors = [
            UIColor.white.withAlphaComponent(1.00).cgColor,
            UIColor.white.withAlphaComponent(1.00).cgColor,
            UIColor.white.withAlphaComponent(0.82).cgColor,
            UIColor.white.withAlphaComponent(0.48).cgColor,
            UIColor.white.withAlphaComponent(0.16).cgColor,
            UIColor.clear.cgColor
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: colors,
            locations: [0.0, 0.10, 0.32, 0.55, 0.78, 1.0]
        ) else {
            return nil
        }

        let radius = CGFloat(height) * 0.44
        context.saveGState()
        context.translateBy(x: CGFloat(width) / 2.0, y: CGFloat(height) / 2.0)
        context.scaleBy(
            x: (CGFloat(width) * 0.47) / radius,
            y: (CGFloat(height) * 0.44) / radius
        )
        context.drawRadialGradient(
            gradient,
            startCenter: .zero,
            startRadius: 0.0,
            endCenter: .zero,
            endRadius: radius,
            options: []
        )
        context.restoreGState()

        guard let image = context.makeImage() else { return nil }
        return try? TextureResource(
            image: image,
            withName: "Astrophage Solid Core Feathered Oval",
            options: .init(semantic: .color)
        )
    }

    private static func makeStarParticleTexture() -> TextureResource? {
        let frameSize = 64
        let frameCount = 8
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: frameSize * frameCount,
            height: frameSize,
            bitsPerComponent: 8,
            bytesPerRow: frameSize * frameCount * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        let centerY = CGFloat(frameSize) / 2.0
        for frame in 0..<frameCount {
            let centerX = CGFloat(frame * frameSize) + CGFloat(frameSize) / 2.0
            let radius = CGFloat([9.0, 24.0, 12.0, 29.0, 10.0, 18.0, 26.0, 13.0][frame])
            let coreAlpha = CGFloat([0.48, 1.0, 0.60, 0.90, 0.44, 1.0, 0.70, 1.0][frame])
            let glowColors = [
                UIColor.white.withAlphaComponent(coreAlpha).cgColor,
                UIColor.white.withAlphaComponent(0.70 * coreAlpha).cgColor,
                UIColor.white.withAlphaComponent(0.24 * coreAlpha).cgColor,
                UIColor.clear.cgColor
            ] as CFArray

            guard let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: glowColors,
                locations: [0.0, 0.12, 0.42, 1.0]
            ) else {
                continue
            }

            context.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: centerX, y: centerY),
                startRadius: 0.0,
                endCenter: CGPoint(x: centerX, y: centerY),
                endRadius: radius,
                options: []
            )

            context.saveGState()
            context.setStrokeColor(UIColor.white.withAlphaComponent(frame == 1 || frame == 7 ? 1.0 : 0.55).cgColor)
            context.setLineWidth(frame == 1 || frame == 7 ? 1.5 : 0.7)
            let rayLength = CGFloat([0.22, 0.92, 0.32, 1.0, 0.18, 0.62, 0.44, 0.82][frame])
            context.move(to: CGPoint(x: centerX - radius * rayLength, y: centerY))
            context.addLine(to: CGPoint(x: centerX + radius * rayLength, y: centerY))
            context.move(to: CGPoint(x: centerX, y: centerY - radius * rayLength))
            context.addLine(to: CGPoint(x: centerX, y: centerY + radius * rayLength))
            context.strokePath()
            context.restoreGState()
        }

        guard let image = context.makeImage() else { return nil }
        return try? TextureResource(
            image: image,
            withName: "Astrophage Sparkle Sequence",
            options: .init(semantic: .color)
        )
    }

}
