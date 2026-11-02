import Foundation
import RealityKit
import UIKit

@MainActor
final class OrbitingSpaceModels: Entity {

    private struct CollisionProxy {
        let center: SIMD3<Float>
        let radius: Float
    }

    private struct Orbiter {
        let entity: Entity
        let collisionRadius: Float
        let sweptCollisionProxies: [CollisionProxy]
        let mass: Float
        let localInertia: SIMD3<Float>
        let infraredOverlay: Entity?
        let isMenuOnly: Bool
        let allowsAutomaticRotation: Bool
        var travelSpeed: Float
        var orbitCenter: SIMD3<Float>
        var orbitRadius: Float
        var orbitPhase: Float
        var orbitAngularVelocity: Float
        var orbitTiltPhase: Float
        var orbitTiltSpeed: Float
        var orbitVerticalPhase: Float
        var orbitVerticalAngularVelocity: Float
        var orbitVerticalAmplitudeScale: Float
        var velocity = SIMD3<Float>.zero
        var isEntering = true
        var entryDelayRemaining: Float = 0.0
        var hasStartedEntryFade = false
        var entryElapsed: Float = 0.0
        var entryFadeElapsed: Float = 0.0
        var spinAxis: SIMD3<Float>
        var spinAngle: Float
        var spinSpeed: Float
        var angularVelocity = SIMD3<Float>.zero
        var isGrabbed = false
        var isFreeFloating = false
        var inputIsEnabled = true
        var collisionHullVertices: [[SIMD3<Float>]] = []
        var isParked = false
        var wasParkedBeforeGrab = false
        var parkedBasePosition: SIMD3<Float>?
        var parkedHoverPhase: Float = 0.0
        var isReturning = false
        var returnDelay: Float = 0.0
        var returnEaseElapsed: Float = 0.0
        var returnDampingDuration: Float = 1.0
        var returnStallElapsed: Float = 0.0
        var returnEscapeCooldown: Float = 0.0
        var grabStartPosition: SIMD3<Float>?
        var orientationReturnStart: simd_quatf?
        var orientationReturnElapsed: Float = 0.0
        var grabOffset: SIMD3<Float>?
        var lastDragPosition: SIMD3<Float>?
        var lastDragTime: TimeInterval?
        var lastDragOrientation: simd_quatf?
        var releaseVelocity = SIMD3<Float>.zero
        var hasManualOrientation = false
        var collisionCooldown: Float = 0.0
        var lastSafePosition: SIMD3<Float> = .zero
        var lastSafeOrientation = simd_quatf(angle: 0, axis: [0, 1, 0])
    }

    private struct PendingModelCollision {
        let firstIndex: Int
        let secondIndex: Int
        let contactPoint: SIMD3<Float>?
        let contactNormal: SIMD3<Float>?
        var sweepProgress: Float? = nil
        var penetration: Float = 0
    }

    private var orbiters: [Orbiter] = []
    private var pendingModelCollisions: [PendingModelCollision] = []
    private var isOrbitingVisible = true
    private var needsInitialPlacement = false
    private var movieModelsAreHidden = false
    private var movieModelFadeIsActive = false
    private var movieModelFadeElapsed: Float = 0.0
    private var movieModelFadeDuration: Float = 1.8
    private var movieModelFadeTarget: Float = 1.0
    private var movieModelFadeStartOpacities: [Int: Float] = [:]
    private var movieModelPresentationOpacities: [Int: Float] = [:]
    private var propsPresentationOpacity: Float = 1.0
    private var propsPresentationStart: Float = 1.0
    private var propsPresentationTarget: Float = 1.0
    private var propsFadeElapsed: Float = 0.0
    private var propsFadeIsActive = false
    private let propsFadeDuration: Float = 0.65
    private var activationBoxPresentationOpacity: Float = 0.0
    private var activationBoxPresentationStart: Float = 0.0
    private var activationBoxPresentationTarget: Float = 0.0
    private var activationBoxFadeElapsed: Float = 0.0
    private let activationBoxFadeDuration: Float = 1.8
    private var initialHomeRevealHasStarted = false
    private let leadingEntrySide: Float = Bool.random() ? -1.0 : 1.0

    private let hoverCenter = SIMD3<Float>(0.0, -0.05, -0.70)
    private let hoverBoxHalfExtents = SIMD3<Float>(1.10, 1.10, 1.10)
    private let comfortableReachMinimum: Float = 0.42
    private let comfortableReachMaximum: Float = 0.78
    private let automaticOrbitMinimumSeparation: Float = 0.34
    private let automaticOrbitSeparationStrength: Float = 0.90
    private let freeFlightDuration: Float = 3.5
    private let returnVelocityTransitionDuration: Float = 1.8
    private let modelRevealInterval: Float = 10.0
    private let modelFadeInDuration: Float = 5.0
    private let activationBoxEntryFadeDuration: Float = 2.4
    private let maximumFreeFlightDistance: Float = 3.0
    private let freeFlightBrakingDistance: Float = 0.85
    private let returnArrivalDistance: Float = 0.055
    private let returnStallThreshold: Float = 0.00008
    private let returnStallDuration: Float = 0.28
    private let returnEscapeDistance: Float = 0.028
    private let returnEscapeCooldownDuration: Float = 0.45
    private let parkedHoverAmplitude: Float = 0.008
    private let parkedHoverAngularSpeed: Float = 1.2

    required init() {
        super.init()
        name = "Orbiting Space Models"
        // RealityKit supplies the environment lighting for content in the
        // mixed space. Apply it at the shared root so both Rocky models,
        // their overlays, and the activation prop use the same lighting
        // context as the user's surroundings.
        components.set(
            EnvironmentLightingConfigurationComponent(
                environmentLightingWeight: 1.0
            )
        )
        let fillLight = Entity()
        fillLight.components.set(DirectionalLightComponent(color: .white, intensity: 250))
        fillLight.orientation = simd_quatf(angle: -.pi / 4, axis: [1, 0, 0])
        addChild(fillLight)
    }

    func loadModels() async {
        guard orbiters.isEmpty else { return }

        let modelNames = [
            "Rockey's Grace-model",
            "Rockey's Grace-ship"
        ]

        for (index, modelName) in modelNames.enumerated() {
            guard let model = await loadModel(named: modelName) else { continue }

            let wrapper = Entity()
            wrapper.name = "Orbiting Space Model \(modelName)"

            let previousTargetSize: Float = index == 0 ? (0.34 / 3.0) : 0.42
            // Grace is 20% smaller and the ship is 10% smaller than the
            // previous presentation sizes (0.102 m and 0.294 m).
            let requestedScale: Float = index == 0 ? 0.72 : 0.63
            normalize(model, targetSize: previousTargetSize * requestedScale)
            model.position = -model.visualBounds(relativeTo: model).center
            disableInteractionComponents(in: model)
            wrapper.addChild(model)

            let visualBounds = model.visualBounds(relativeTo: wrapper)
            let colliderSize = simd_max(
                visualBounds.extents * 1.05,
                SIMD3<Float>(repeating: 0.025)
            )
            let collisionRadius = max(
                colliderSize.x,
                colliderSize.y,
                colliderSize.z
            ) * 0.5
            let mass: Float = index == 0 ? 2.4 : 5.2
            let localInertia = boxInertia(size: colliderSize, mass: mass)
                * SpaceModelPhysics.rotationalInertiaMultiplier
            let colliderShapes: [ShapeResource]
            let sweptCollisionProxies: [CollisionProxy]
            let collisionHullVertices: [[SIMD3<Float>]]
            do {
                let collider = try await RockyMeshCollider.load(
                    named: index == 0 ? "RockyModelCollision" : "RockyShipCollision",
                    bounds: visualBounds
                )
                colliderShapes = collider.shapes
                collisionHullVertices = collider.vertices
                // These bounds are only a cheap rejection test. They never
                // generate an impact; the actual convex shapes do that.
                sweptCollisionProxies = [CollisionProxy(
                    center: visualBounds.center,
                    radius: simd_length(visualBounds.extents) * 0.5
                )]
                AppTrace.mark("COLLIDER \(modelName) mesh hulls=\(colliderShapes.count)")
            } catch {
                // Keep a changed/unavailable asset usable and make recooking
                // visible in the trace. Never silently substitute a large box.
                AppTrace.mark("COLLIDER \(modelName) recook required: \(error)")
                guard let fallback = await generateCompoundCollider(
                    from: model, relativeTo: wrapper, sectionCount: 24
                ) else {
                    AppTrace.mark("COLLIDER \(modelName) could not build geometry")
                    continue
                }
                colliderShapes = fallback.shapes
                collisionHullVertices = []
                sweptCollisionProxies = fallback.proxies
            }

            // A forgiving input-only target also covers the thin parts of the
            // small model. Keep it separate from the physical collision shapes.
            let grabSize = simd_max(
                colliderSize + SIMD3<Float>(repeating: 0.035),
                SIMD3<Float>(repeating: 0.065)
            )
            let grabProxy = Entity()
            grabProxy.name = "\(modelName) Grab Target"
            grabProxy.components.set(CollisionComponent(
                shapes: [ShapeResource.generateBox(size: grabSize)
                    .offsetBy(translation: visualBounds.center)],
                mode: .trigger,
                filter: CollisionFilter(group: CollisionGroup(rawValue: 1 << 30), mask: [])
            ))
            // Rocky models are hand-near interaction targets only. Restricting
            // this proxy to direct input prevents a distant gaze-and-pinch
            // gesture from rotating or moving the model.
            grabProxy.components.set(
                InputTargetComponent(allowedInputTypes: .direct)
            )
            grabProxy.components.set(ManipulationComponent.HitTarget(redirectedEntity: wrapper))
            wrapper.addChild(grabProxy)

            let infraredOverlay = model.clone(recursive: true)
            infraredOverlay.name = "\(modelName) Infrared Overlay"
            infraredOverlay.scale *= SIMD3<Float>(repeating: 1.002)
            configureInfraredOverlay(in: infraredOverlay)
            disableInteractionComponents(in: infraredOverlay)
            infraredOverlay.components.set(OpacityComponent(opacity: 0.0))
            wrapper.addChild(infraredOverlay)
            wrapper.components.set(
                InputTargetComponent(allowedInputTypes: .direct)
            )
            wrapper.components.set(CollisionComponent(
                shapes: colliderShapes,
                collisionOptions: .fullContactInformation,
                filter: CollisionFilter(
                    group: CollisionGroup(rawValue: 1 << (8 + index)), mask: .all
                )
            ))
            wrapper.components.set(OpacityComponent(opacity: 0.0))
            wrapper.components.set(PhysicsBodyComponent(
                shapes: colliderShapes,
                mass: mass,
                material: .generate(
                    friction: SpaceModelPhysics.friction,
                    restitution: SpaceModelPhysics.restitution
                ),
                mode: .kinematic
            ))
            wrapper.components.set(naturalManipulation(inertia: .low))
            wrapper.position = horizontalEntryPosition(forRevealIndex: index)
            addChild(wrapper)

            orbiters.append(Orbiter(
                entity: wrapper,
                collisionRadius: collisionRadius,
                sweptCollisionProxies: sweptCollisionProxies,
                mass: mass,
                localInertia: localInertia,
                infraredOverlay: infraredOverlay,
                isMenuOnly: true,
                allowsAutomaticRotation: true,
                travelSpeed: index == 0 ? 0.0275 : 0.0225,
                orbitCenter: hoverCenter + SIMD3<Float>(
                    index == 0 ? -0.25 : 0.27,
                    index == 0 ? 0.13 : -0.12,
                    index == 0 ? 0.05 : -0.05
                ),
                orbitRadius: 0.58,
                orbitPhase: index == 0 ? 0.4 : 3.1,
                orbitAngularVelocity: index == 0 ? 0.025 : -0.019,
                orbitTiltPhase: Float.random(in: 0...(2.0 * .pi)),
                orbitTiltSpeed: index == 0 ? 0.16 : -0.12,
                orbitVerticalPhase: Float.random(in: 0...(2.0 * .pi)),
                orbitVerticalAngularVelocity: index == 0
                    ? Float.random(in: 0.018...0.031)
                    : Float.random(in: -0.029 ... -0.014),
                orbitVerticalAmplitudeScale: Float.random(in: 0.52...0.88),
                entryDelayRemaining: .greatestFiniteMagnitude,
                spinAxis: simd_normalize(SIMD3<Float>(
                    index == 0 ? 0.28 : -0.18,
                    index == 0 ? 1.0 : 0.85,
                    index == 0 ? 0.16 : 0.32
                )),
                spinAngle: 0.0,
                spinSpeed: index == 0 ? 0.08 : -0.07,
                lastSafePosition: wrapper.position
            ))
            orbiters[orbiters.count - 1].collisionHullVertices = collisionHullVertices
            setRockyInputEnabled(false, for: orbiters.count - 1)
        }
    }

    func startInitialHomeRevealIfNeeded() {
        guard !initialHomeRevealHasStarted else { return }
        initialHomeRevealHasStarted = true
        var homeRevealIndex: Float = 0.0

        for index in orbiters.indices where orbiters[index].isMenuOnly {
            orbiters[index].entryDelayRemaining = 5.0
                + homeRevealIndex * modelRevealInterval
            orbiters[index].entryElapsed = 1.0
            orbiters[index].entryFadeElapsed = 0.65
            homeRevealIndex += 1.0
        }

        AppTrace.mark(
            "ORBIT loaded Home visible; first model reveal begins in 5.0s"
        )
    }

    func presentHomeFinalStateImmediately() {
        initialHomeRevealHasStarted = true

        for index in orbiters.indices where orbiters[index].isMenuOnly {
            let target = separatedOrbitalTarget(for: index)
            orbiters[index].entity.isEnabled = true
            orbiters[index].entity.position = target
            orbiters[index].lastSafePosition = target
            orbiters[index].entryDelayRemaining = 0.0
            orbiters[index].entryElapsed = 1.0
            orbiters[index].entryFadeElapsed = modelFadeInDuration
            orbiters[index].hasStartedEntryFade = true
            orbiters[index].isEntering = false
            orbiters[index].entity.components.set(
                OpacityComponent(opacity: 1.0)
            )
        }
    }

    func addActivationBox(
        _ activationBox: ActivationBox
    ) async -> [Entity] {
        guard index(for: activationBox) == nil else { return [activationBox] }

        let visualBounds = activationBox.visualBounds(relativeTo: activationBox)
        let colliderSize = simd_max(
            visualBounds.extents * 1.05,
            SIMD3<Float>(repeating: 0.04)
        )
        let boxColliderShape = ShapeResource.generateBox(size: colliderSize)
            .offsetBy(translation: visualBounds.center)
        let collisionRadius = max(colliderSize.x, colliderSize.y, colliderSize.z) * 0.5
        let mass: Float = 3.8
        let localInertia = boxInertia(size: colliderSize, mass: mass)
        let compoundCollider = await generateCompoundCollider(
            from: activationBox,
            relativeTo: activationBox,
            sectionCount: 8
        )
        let colliderShapes = compoundCollider?.shapes ?? [boxColliderShape]
        let collisionProxies = compoundCollider?.proxies ?? [CollisionProxy(
            center: visualBounds.center,
            radius: collisionRadius
        )]

        // Match the Rocky props: this object is manipulated only by direct
        // hand contact. There is intentionally no gaze/indirect tap target.
        activationBox.components.set(
            InputTargetComponent(allowedInputTypes: .direct)
        )

        if compoundCollider != nil {
            let grabProxy = Entity()
            grabProxy.name = "Petrova Indicator Grab Target"
            grabProxy.components.set(CollisionComponent(
                shapes: [boxColliderShape],
                mode: .trigger,
                filter: CollisionFilter(
                    group: CollisionGroup(rawValue: 1 << 30),
                    mask: []
                )
            ))
            grabProxy.components.set(
                InputTargetComponent(allowedInputTypes: .direct)
            )
            grabProxy.components.set(
                ManipulationComponent.HitTarget(redirectedEntity: activationBox)
            )
            activationBox.addChild(grabProxy)
        }
        activationBox.components.set(CollisionComponent(
            shapes: colliderShapes,
            collisionOptions: .fullContactInformation
        ))
        activationBox.components.set(PhysicsBodyComponent(
            shapes: colliderShapes,
            mass: mass,
            material: .generate(friction: 0.32, restitution: 0.08),
            mode: .kinematic
        ))

        var activationOrbiter = Orbiter(
            entity: activationBox,
            collisionRadius: collisionRadius,
            sweptCollisionProxies: collisionProxies,
            mass: mass,
            localInertia: localInertia,
            infraredOverlay: nil,
            isMenuOnly: false,
            allowsAutomaticRotation: true,
            travelSpeed: 0.024,
            orbitCenter: hoverCenter + SIMD3<Float>(0.0, 0.10, 0.01),
            orbitRadius: 0.58,
            orbitPhase: 5.15,
            orbitAngularVelocity: 0.021,
            orbitTiltPhase: Float.random(in: 0...(2.0 * .pi)),
            orbitTiltSpeed: 0.10,
            orbitVerticalPhase: Float.random(in: 0...(2.0 * .pi)),
            orbitVerticalAngularVelocity: Float.random(in: 0.015...0.026),
            orbitVerticalAmplitudeScale: Float.random(in: 0.48...0.72),
            entryDelayRemaining: 2.0 * modelRevealInterval,
            spinAxis: simd_normalize(SIMD3<Float>(0.12, 1.0, 0.08)),
            spinAngle: 0.0,
            spinSpeed: 0.045,
            lastSafePosition: .zero
        )
        activationBox.position = horizontalEntryPosition(
            forRevealIndex: orbiters.count
        )
        activationBox.orientation = levelFacingOrigin(from: activationBox.position)
        activationBox.components.set(OpacityComponent(opacity: 0.0))
        activationBox.isEnabled = false
        activationOrbiter.orientationReturnStart = activationBox.orientation
        activationOrbiter.orientationReturnElapsed = 0.0
        activationOrbiter.lastSafePosition = activationBox.position
        activationBox.setParent(self, preservingWorldTransform: false)
        orbiters.append(activationOrbiter)
        return [activationBox]
    }

    func update(deltaTime: Float) {
        guard !orbiters.isEmpty else { return }
        // Avoid integrating a large jump after suspension or a stalled frame.
        let deltaTime = min(max(deltaTime, 0), 1.0 / 30.0)
        guard deltaTime > 0 else { return }

        for index in orbiters.indices {
            guard orbiters[index].entity.isEnabled else { continue }

            if orbiters[index].entryDelayRemaining > 0.0 {
                orbiters[index].entryDelayRemaining = max(
                    0.0,
                    orbiters[index].entryDelayRemaining - deltaTime
                )
                orbiters[index].lastSafePosition = orbiters[index].entity.position
                continue
            }

            if orbiters[index].isParked {
                orbiters[index].collisionCooldown = max(
                    0.0,
                    orbiters[index].collisionCooldown - deltaTime
                )
                if let basePosition = orbiters[index].parkedBasePosition {
                    orbiters[index].parkedHoverPhase += parkedHoverAngularSpeed
                        * deltaTime
                    var hoverPosition = basePosition
                    hoverPosition.y += sin(orbiters[index].parkedHoverPhase)
                        * parkedHoverAmplitude
                    orbiters[index].entity.position = hoverPosition
                    orbiters[index].lastSafePosition = hoverPosition
                }
                continue
            }

            orbiters[index].spinAngle += orbiters[index].spinSpeed * deltaTime
            orbiters[index].orbitPhase += orbiters[index].orbitAngularVelocity * deltaTime
            orbiters[index].orbitTiltPhase += orbiters[index].orbitTiltSpeed * deltaTime
            orbiters[index].orbitVerticalPhase += orbiters[index].orbitVerticalAngularVelocity
                * deltaTime
            orbiters[index].collisionCooldown = max(0.0, orbiters[index].collisionCooldown - deltaTime)
            orbiters[index].returnEscapeCooldown = max(
                0.0,
                orbiters[index].returnEscapeCooldown - deltaTime
            )

            if orbiters[index].isGrabbed {
                captureNativeGrabMotion(for: index)
                continue
            }

            // Entry/presentation remains choreographed; settled Rocky props drift freely.
            if orbiters[index].isMenuOnly,
               !orbiters[index].isEntering,
               !orbiters[index].isFreeFloating,
               !orbiters[index].isReturning {
                beginWeightlessFlight(for: index, seedSpin: true)
            }
            integrateImpactRotation(for: index, deltaTime: deltaTime)
            if orbiters[index].isFreeFloating {
                var position = orbiters[index].entity.position
                var velocity = orbiters[index].velocity
                orbiters[index].lastSafePosition = position
                if !orbiters[index].isReturning {
                    // Very gentle guidance keeps ordinary drift around the user.
                    // Impacts remain visible; no timer or sudden velocity reset.
                    let toTarget = orbitalTarget(for: orbiters[index]) - position
                    let distance = simd_length(toTarget)
                    let desiredVelocity = distance > 0.001
                        ? toTarget / distance * orbiters[index].travelSpeed : .zero
                    velocity = simd_mix(velocity, desiredVelocity,
                        SIMD3<Float>(repeating: 1 - exp(-deltaTime / 18.0)))
                }
                SpaceModelPhysics.advanceFlight(
                    position: &position, velocity: &velocity,
                    deltaTime: deltaTime,
                    freeRadius: orbiters[index].isReturning
                        ? maximumFreeFlightDistance - freeFlightBrakingDistance : 1.15
                )
                orbiters[index].entity.position = position
                orbiters[index].velocity = velocity
                if orbiters[index].isReturning {
                    orbiters[index].returnDelay = max(0, orbiters[index].returnDelay - deltaTime)
                    orbiters[index].releaseVelocity = velocity
                    if orbiters[index].returnDelay == 0 {
                        orbiters[index].isFreeFloating = false
                    }
                }
                continue
            }

            if orbiters[index].returnDelay > 0.0 {
                advanceFreeFlight(for: index, deltaTime: deltaTime)
                continue
            }

            let driftPhase = orbiters[index].spinAngle
            let target = separatedOrbitalTarget(for: index)
            let targetVector = target - orbiters[index].entity.position
            let targetDistance = simd_length(targetVector)
            let targetDirection = targetDistance > 0.001
                ? targetVector / targetDistance
                : SIMD3<Float>.zero
            if orbiters[index].isEntering {
                orbiters[index].entryElapsed += deltaTime
            }
            if orbiters[index].isEntering,
               !orbiters[index].hasStartedEntryFade,
               orbiters[index].entryElapsed >= 1.0 {
                orbiters[index].hasStartedEntryFade = true
            }
            if orbiters[index].hasStartedEntryFade,
               orbiters[index].entryFadeElapsed
                    < (orbiters[index].isMenuOnly
                        ? modelFadeInDuration
                        : activationBoxEntryFadeDuration) {
                let entryFadeDuration = orbiters[index].isMenuOnly
                    ? modelFadeInDuration
                    : activationBoxEntryFadeDuration
                orbiters[index].entryFadeElapsed = min(
                    entryFadeDuration,
                    orbiters[index].entryFadeElapsed + deltaTime
                )
                let fade = smoothstep(
                    orbiters[index].entryFadeElapsed / entryFadeDuration
                )
                orbiters[index].entity.components.set(OpacityComponent(opacity: fade))
            }
            if orbiters[index].isReturning {
                orbiters[index].returnEaseElapsed += deltaTime
            }
            let desiredSpeed: Float
            if orbiters[index].isEntering {
                let maximumEntrySpeed: Float = orbiters[index].isMenuOnly
                    ? (index == 0 ? 0.052 : 0.047)
                    : 0.055
                desiredSpeed = max(
                    orbiters[index].travelSpeed,
                    min(maximumEntrySpeed, targetDistance / 4.0)
                )
            } else if orbiters[index].isReturning {
                desiredSpeed = max(
                    orbiters[index].travelSpeed,
                    min(0.32, targetDistance / 2.2)
                )
            } else {
                desiredSpeed = orbiters[index].travelSpeed
            }
            let desiredVelocity = targetDirection * desiredSpeed
            if orbiters[index].isReturning {
                let dampingProgress = smoothstep(min(
                    1.0,
                    orbiters[index].returnEaseElapsed / orbiters[index].returnDampingDuration
                ))
                orbiters[index].velocity = simd_mix(
                    orbiters[index].releaseVelocity,
                    desiredVelocity,
                    SIMD3<Float>(repeating: dampingProgress)
                )
            } else {
                let steering = min(1.0, deltaTime * 0.55)
                orbiters[index].velocity = simd_mix(
                    orbiters[index].velocity,
                    desiredVelocity,
                    SIMD3<Float>(repeating: steering)
                )
            }
            orbiters[index].lastSafePosition = orbiters[index].entity.position
            let positionBeforeReturnStep = orbiters[index].entity.position
            orbiters[index].entity.position += orbiters[index].velocity * deltaTime

            if orbiters[index].isReturning {
                let movedDistance = simd_distance(
                    positionBeforeReturnStep,
                    orbiters[index].entity.position
                )
                if targetDistance > returnArrivalDistance,
                   movedDistance < returnStallThreshold,
                   orbiters[index].returnEscapeCooldown <= 0.0 {
                    orbiters[index].returnStallElapsed += deltaTime
                } else if movedDistance >= returnStallThreshold {
                    orbiters[index].returnStallElapsed = 0.0
                }

                if orbiters[index].returnStallElapsed >= returnStallDuration {
                    recoverBlockedReturn(for: index, target: target)
                }
            }


            if orbiters[index].isReturning,
               simd_distance(orbiters[index].entity.position, target)
                    < returnArrivalDistance {
                orbiters[index].isReturning = false
                orbiters[index].returnEaseElapsed = 0.0
                orbiters[index].returnDampingDuration = returnVelocityTransitionDuration
                orbiters[index].returnStallElapsed = 0.0
                if orbiters[index].isMenuOnly {
                    beginWeightlessFlight(for: index)
                } else {
                    orbiters[index].orientationReturnStart = orbiters[index].entity.orientation
                    orbiters[index].orientationReturnElapsed = 0.0
                    orbiters[index].hasManualOrientation = false
                    orbiters[index].angularVelocity = .zero
                }
            }
            if orbiters[index].isEntering,
               orbiters[index].entryFadeElapsed >= modelFadeInDuration,
               simd_distance(orbiters[index].entity.position, target) < 0.16 {
                orbiters[index].isEntering = false
                orbiters[index].entity.components.set(OpacityComponent(opacity: 1.0))
            }

            let primaryRotation = simd_quatf(
                angle: orbiters[index].spinAngle,
                axis: orbiters[index].spinAxis
            )
            let tumbleX = simd_quatf(
                angle: sin(driftPhase * 0.41) * 0.22,
                axis: [1.0, 0.0, 0.0]
            )
            let tumbleY = simd_quatf(
                angle: sin(driftPhase * 0.29 + 0.7) * 0.18,
                axis: [0.0, 1.0, 0.0]
            )
            let tumbleZ = simd_quatf(
                angle: sin(driftPhase * 0.53 + 1.8) * 0.16,
                axis: [0.0, 0.0, 1.0]
            )
            if !orbiters[index].allowsAutomaticRotation {
                if !orbiters[index].isReturning {
                    orbiters[index].entity.orientation = levelFacingOrigin(
                        from: orbiters[index].entity.position
                    )
                }
            } else if let releaseOrientation = orbiters[index].orientationReturnStart {
                orbiters[index].orientationReturnElapsed += deltaTime
                let blend = smoothstep(min(1.0, orbiters[index].orientationReturnElapsed / 2.0))
                orbiters[index].entity.orientation = simd_slerp(releaseOrientation, primaryRotation * tumbleX * tumbleY * tumbleZ, blend)
                if blend == 1.0 {
                    orbiters[index].orientationReturnStart = nil
                }
            } else if !orbiters[index].hasManualOrientation {
                orbiters[index].entity.orientation = primaryRotation * tumbleX * tumbleY * tumbleZ
            }
        }

        queueSweptModelCollisions()
        resolvePendingModelCollisions(deltaTime: deltaTime)
        keepOrbitersInsideHoverBox()
        updateMovieModelPresentation(deltaTime: deltaTime)
        updatePropsPresentation(deltaTime: deltaTime)
        updateActivationBoxPresentation(deltaTime: deltaTime)
        for index in orbiters.indices where orbiters[index].isMenuOnly {
            let opacity = orbiters[index].entity.components[OpacityComponent.self]?.opacity ?? 0
            setRockyInputEnabled(
                orbiters[index].isGrabbed
                    || (orbiters[index].entity.isEnabled
                        && orbiters[index].entryDelayRemaining <= 0
                        && opacity > 0.01),
                for: index
            )
        }
        for index in orbiters.indices where orbiters[index].entity.isEnabled {
            orbiters[index].lastSafePosition = orbiters[index].entity.position
            orbiters[index].lastSafeOrientation = orbiters[index].entity.orientation
        }
        needsInitialPlacement = false
    }

    func setActiveExperiencePresentation(
        _ isActive: Bool,
        showsActivationBox: Bool
    ) {
        setActiveExperienceModelsHidden(isActive)
        setActivationBoxVisible(showsActivationBox)
    }

    func setActiveExperienceModelsHidden(_ isActive: Bool) {
        guard movieModelsAreHidden != isActive else { return }
        if !isActive {
            movieModelsAreHidden = false
            beginRockyModelsSideReentry(source: "Home")
            AppTrace.mark(
                "ORBIT Home return started: Rocky models re-enter and fade in"
            )
            return
        }

        movieModelsAreHidden = true
        movieModelFadeElapsed = 0.0
        movieModelFadeDuration = 1.8
        movieModelFadeTarget = 0.0
        movieModelFadeIsActive = true
        movieModelFadeStartOpacities.removeAll(keepingCapacity: true)

        for index in orbiters.indices where orbiters[index].isMenuOnly {
            let currentOpacity = movieModelPresentationOpacities[index]
                ?? naturalPresentationOpacity(for: index)
            movieModelFadeStartOpacities[index] = currentOpacity
            movieModelPresentationOpacities[index] = currentOpacity
        }

        AppTrace.mark(
            "ORBIT active experience models fade out duration=\(movieModelFadeDuration)"
        )
    }

    private func beginRockyModelsSideReentry(source: String) {
        movieModelFadeElapsed = 0.0
        movieModelFadeDuration = 3.5
        movieModelFadeTarget = 1.0
        movieModelFadeIsActive = true
        movieModelFadeStartOpacities.removeAll(keepingCapacity: true)
        let returnLeadingSide: Float = Bool.random() ? -1.0 : 1.0

        for index in orbiters.indices where orbiters[index].isMenuOnly {
            let wasEnabled = orbiters[index].entity.isEnabled

            if orbiters[index].isParked {
                let parkedOpacity: Float = wasEnabled
                    ? (movieModelPresentationOpacities[index]
                        ?? naturalPresentationOpacity(for: index))
                    : 0.0
                movieModelFadeStartOpacities[index] = parkedOpacity
                movieModelPresentationOpacities[index] = parkedOpacity
                orbiters[index].entity.isEnabled = true
                orbiters[index].entryDelayRemaining = 0.0
                orbiters[index].isEntering = false
                orbiters[index].velocity = .zero
                orbiters[index].releaseVelocity = .zero
                orbiters[index].angularVelocity = .zero
                orbiters[index].lastSafePosition = orbiters[index].entity.position
                orbiters[index].entity.components.set(OpacityComponent(
                    opacity: parkedOpacity
                ))
                continue
            }

            movieModelFadeStartOpacities[index] = 0.0
            movieModelPresentationOpacities[index] = 0.0

            orbiters[index].entity.isEnabled = true
            orbiters[index].entryDelayRemaining = 0.0
            orbiters[index].isEntering = true
            orbiters[index].isFreeFloating = false
            orbiters[index].entryElapsed = 1.0
            orbiters[index].hasStartedEntryFade = true
            orbiters[index].entryFadeElapsed = modelFadeInDuration
            orbiters[index].isGrabbed = false
            orbiters[index].isReturning = false
            orbiters[index].returnDelay = 0.0
            orbiters[index].returnEaseElapsed = 0.0
            orbiters[index].returnStallElapsed = 0.0
            orbiters[index].returnEscapeCooldown = 0.0
            orbiters[index].releaseVelocity = .zero
            orbiters[index].velocity = .zero
            orbiters[index].angularVelocity = .zero
            orbiters[index].hasManualOrientation = false
            orbiters[index].orientationReturnStart = orbiters[index].entity.orientation
            orbiters[index].orientationReturnElapsed = 0.0
            orbiters[index].orbitPhase = Float.random(in: 0...(2.0 * .pi))
            orbiters[index].orbitTiltPhase = Float.random(in: 0...(2.0 * .pi))
            orbiters[index].orbitVerticalPhase = Float.random(in: 0...(2.0 * .pi))
            orbiters[index].entity.position = horizontalEntryPosition(
                forRevealIndex: index,
                leadingSide: returnLeadingSide
            )
            orbiters[index].collisionCooldown = movieModelFadeDuration
            orbiters[index].lastSafePosition = orbiters[index].entity.position
            orbiters[index].entity.components.set(OpacityComponent(opacity: 0.0))
        }

        AppTrace.mark(
            "ORBIT \(source) models left-right re-entry "
                + "duration=\(movieModelFadeDuration)"
        )
    }

    private func updateMovieModelPresentation(deltaTime: Float) {
        guard movieModelFadeIsActive || movieModelsAreHidden else { return }

        if movieModelFadeIsActive {
            movieModelFadeElapsed = min(
                movieModelFadeDuration,
                movieModelFadeElapsed + deltaTime
            )
        }
        let progress = movieModelFadeIsActive
            ? smootherstep(movieModelFadeElapsed / max(movieModelFadeDuration, 0.0001))
            : 1.0

        for index in orbiters.indices where orbiters[index].isMenuOnly {
            let startOpacity = movieModelFadeStartOpacities[index]
                ?? movieModelPresentationOpacities[index]
                ?? naturalPresentationOpacity(for: index)
            let opacity = startOpacity
                + (movieModelFadeTarget - startOpacity) * progress
            movieModelPresentationOpacities[index] = opacity
            orbiters[index].entity.components.set(OpacityComponent(opacity: opacity))
        }

        guard movieModelFadeIsActive,
              movieModelFadeElapsed >= movieModelFadeDuration else { return }

        movieModelFadeIsActive = false
        if movieModelsAreHidden {
            for index in orbiters.indices where orbiters[index].isMenuOnly {
                orbiters[index].entity.components.set(OpacityComponent(opacity: 0.0))
                orbiters[index].entity.isEnabled = false
            }
        } else {
            movieModelFadeStartOpacities.removeAll(keepingCapacity: true)
            movieModelPresentationOpacities.removeAll(keepingCapacity: true)
        }
    }

    private func naturalPresentationOpacity(for index: Int) -> Float {
        guard orbiters.indices.contains(index),
              orbiters[index].entryDelayRemaining <= 0.0 else { return 0.0 }
        guard orbiters[index].isEntering else { return 1.0 }
        guard orbiters[index].hasStartedEntryFade else { return 0.0 }
        let entryFadeDuration = orbiters[index].isMenuOnly
            ? modelFadeInDuration
            : activationBoxEntryFadeDuration
        return smoothstep(min(
            1.0,
            orbiters[index].entryFadeElapsed / max(entryFadeDuration, 0.0001)
        ))
    }

    private func updatePropsPresentation(deltaTime: Float) {
        guard propsFadeIsActive || propsPresentationOpacity != 1.0 else {
            return
        }

        if propsFadeIsActive {
            propsFadeElapsed = min(
                propsFadeDuration,
                propsFadeElapsed + deltaTime
            )
            let progress = smootherstep(
                propsFadeElapsed / max(propsFadeDuration, 0.0001)
            )
            propsPresentationOpacity = propsPresentationStart
                + (propsPresentationTarget - propsPresentationStart) * progress
        }

        for index in orbiters.indices where orbiters[index].isMenuOnly {
            guard orbiters[index].entity.isEnabled else { continue }
            let baseOpacity = movieModelPresentationOpacities[index]
                ?? naturalPresentationOpacity(for: index)
            orbiters[index].entity.components.set(OpacityComponent(
                opacity: baseOpacity * propsPresentationOpacity
            ))
        }

        guard propsFadeIsActive,
              propsFadeElapsed >= propsFadeDuration else { return }

        propsFadeIsActive = false
        if propsPresentationTarget == 0.0 {
            for index in orbiters.indices where orbiters[index].isMenuOnly {
                orbiters[index].entity.components.set(
                    OpacityComponent(opacity: 0.0)
                )
                orbiters[index].entity.isEnabled = false
            }
        }
    }

    func setActivationBoxVisible(_ isVisible: Bool) {
        guard let index = orbiters.firstIndex(where: { !$0.isMenuOnly }) else { return }
        let newTarget: Float = isVisible ? 1.0 : 0.0
        guard activationBoxPresentationTarget != newTarget else { return }

        activationBoxPresentationStart = activationBoxPresentationOpacity
        activationBoxPresentationTarget = newTarget
        activationBoxFadeElapsed = 0.0

        if isVisible {
            orbiters[index].entity.isEnabled = true
            orbiters[index].entryDelayRemaining = 0.0
            orbiters[index].entryElapsed = max(
                orbiters[index].entryElapsed,
                1.0
            )
            orbiters[index].hasStartedEntryFade = true
            orbiters[index].lastSafePosition = orbiters[index].entity.position
        }

        let visibilityAction = isVisible ? "fade in" : "fade out"
        AppTrace.mark(
            "ORBIT activation box \(visibilityAction) "
                + "duration=\(activationBoxFadeDuration)"
        )
    }

    private func updateActivationBoxPresentation(deltaTime: Float) {
        guard let index = orbiters.firstIndex(where: { !$0.isMenuOnly }),
              orbiters[index].entity.isEnabled else { return }

        if activationBoxPresentationOpacity != activationBoxPresentationTarget {
            activationBoxFadeElapsed = min(
                activationBoxFadeDuration,
                activationBoxFadeElapsed + deltaTime
            )
            let progress = smootherstep(
                activationBoxFadeElapsed / activationBoxFadeDuration
            )
            activationBoxPresentationOpacity = activationBoxPresentationStart
                + (activationBoxPresentationTarget - activationBoxPresentationStart)
                    * progress
        }

        let naturalOpacity = naturalPresentationOpacity(for: index)
        orbiters[index].entity.components.set(OpacityComponent(
            opacity: naturalOpacity * activationBoxPresentationOpacity
        ))

        if activationBoxPresentationTarget == 0.0,
           activationBoxPresentationOpacity <= 0.0001 {
            orbiters[index].entity.isEnabled = false
        }
    }

    func setOrbitingVisible(_ isVisible: Bool) {
        guard isOrbitingVisible != isVisible else { return }
        isOrbitingVisible = isVisible
        propsPresentationStart = propsPresentationOpacity
        propsPresentationTarget = isVisible ? 1.0 : 0.0
        propsFadeElapsed = 0.0
        propsFadeIsActive = true

        if isVisible {
            for index in orbiters.indices where orbiters[index].isMenuOnly {
                orbiters[index].entity.isEnabled = true
                orbiters[index].lastSafePosition = orbiters[index].entity.position
            }
        }

        needsInitialPlacement = false
        AppTrace.mark(
            "ORBIT props \(isVisible ? "fade in" : "fade out") "
                + "duration=\(propsFadeDuration)"
        )
    }

    func beginGrab(_ grabbedEntity: Entity) {
        guard let index = index(for: grabbedEntity) else { return }
        guard orbiters[index].entryDelayRemaining <= 0.0 else { return }
        if orbiters[index].isGrabbed {
            // RealityKit can start a fresh manipulation after a cancelled
            // tracking sample without a clean logical release in between.
            // Treat it as a resumed grab and start a fresh release sample.
            orbiters[index].grabStartPosition = orbiters[index].entity.position
            orbiters[index].grabOffset = nil
            orbiters[index].lastDragPosition = orbiters[index].entity.position
            orbiters[index].lastDragOrientation = orbiters[index].entity.orientation
            orbiters[index].lastDragTime = ProcessInfo.processInfo.systemUptime
            orbiters[index].releaseVelocity = .zero
            orbiters[index].velocity = .zero
            orbiters[index].angularVelocity = .zero
            AppTrace.mark("ORBIT grab resumed index=\(index)")
            return
        }
        if orbiters[index].isMenuOnly {
            // Hand control takes over immediately, even during the entrance.
            // This also completes the fade instead of freezing a translucent prop.
            beginWeightlessFlight(for: index)
            orbiters[index].collisionCooldown = 0
        }
        orbiters[index].isGrabbed = true
        orbiters[index].isFreeFloating = false
        orbiters[index].wasParkedBeforeGrab = orbiters[index].isParked
        orbiters[index].isParked = false
        orbiters[index].isReturning = false
        orbiters[index].returnDelay = 0.0
        orbiters[index].returnEaseElapsed = 0.0
        orbiters[index].returnStallElapsed = 0.0
        orbiters[index].returnEscapeCooldown = 0.0
        orbiters[index].returnDampingDuration = returnVelocityTransitionDuration
        orbiters[index].grabStartPosition = orbiters[index].entity.position
        orbiters[index].orientationReturnStart = nil
        orbiters[index].orientationReturnElapsed = 0.0
        orbiters[index].grabOffset = nil
        orbiters[index].lastDragPosition = orbiters[index].entity.position
        orbiters[index].lastDragOrientation = orbiters[index].entity.orientation
        orbiters[index].lastDragTime = ProcessInfo.processInfo.systemUptime
        orbiters[index].releaseVelocity = .zero
        orbiters[index].velocity = .zero
        orbiters[index].angularVelocity = .zero
    }

    func noteGrabHandOff(_ grabbedEntity: Entity) {
        guard let index = index(for: grabbedEntity), orbiters[index].isGrabbed else {
            return
        }

        // Keep the grab session alive, but do not interpret the handoff gap
        // as a high-speed throw when the next hand supplies a new transform.
        orbiters[index].lastDragPosition = orbiters[index].entity.position
        orbiters[index].lastDragOrientation = orbiters[index].entity.orientation
        orbiters[index].lastDragTime = ProcessInfo.processInfo.systemUptime
        orbiters[index].releaseVelocity = .zero
        orbiters[index].angularVelocity = .zero
        AppTrace.mark("ORBIT grab handoff index=\(index)")
    }

    func keepGrabAfterCancellation(_ grabbedEntity: Entity) {
        guard let index = index(for: grabbedEntity), orbiters[index].isGrabbed else {
            return
        }

        // WillRelease can report a cancelled interaction during a brief hand
        // tracking interruption. Do not transition to free flight; keep the
        // object stationary until RealityKit resumes or the user releases it.
        orbiters[index].lastDragPosition = orbiters[index].entity.position
        orbiters[index].lastDragOrientation = orbiters[index].entity.orientation
        orbiters[index].lastDragTime = ProcessInfo.processInfo.systemUptime
        orbiters[index].releaseVelocity = .zero
        orbiters[index].velocity = .zero
        orbiters[index].angularVelocity = .zero
        AppTrace.mark("ORBIT cancelled grab retained index=\(index)")
    }

    func moveGrabbed(_ grabbedEntity: Entity, to position: SIMD3<Float>) {
        guard let index = index(for: grabbedEntity) else { return }
        if orbiters[index].grabOffset == nil {
            orbiters[index].grabOffset = orbiters[index].entity.position - position
        }
        let newPosition = position + (orbiters[index].grabOffset ?? .zero)
        orbiters[index].entity.position = newPosition
        captureNativeGrabMotion(for: index)
    }

    private func captureNativeGrabMotion(for index: Int) {
        let newPosition = orbiters[index].entity.position
        let newOrientation = orbiters[index].entity.orientation
        let now = ProcessInfo.processInfo.systemUptime
        if let previousPosition = orbiters[index].lastDragPosition,
           let previousOrientation = orbiters[index].lastDragOrientation,
           let previousTime = orbiters[index].lastDragTime {
            let elapsed = Float(now - previousTime)
            // Multiple gesture/update callbacks can occur in the same frame.
            // Keep the previous sample until enough time has elapsed.
            guard elapsed >= 1.0 / 240.0 else { return }
            if elapsed < 0.15 {
                let blend = SIMD3<Float>(repeating: 1 - exp(-elapsed / 0.045))
                orbiters[index].releaseVelocity = simd_mix(
                    orbiters[index].releaseVelocity,
                    (newPosition - previousPosition) / elapsed, blend
                )
                orbiters[index].angularVelocity = simd_mix(
                    orbiters[index].angularVelocity,
                    SpaceModelPhysics.angularVelocity(
                        from: previousOrientation, to: newOrientation, elapsed: elapsed
                    ), blend
                )
            } else {
                // A tracking interruption must not turn into a throw.
                orbiters[index].releaseVelocity = .zero
                orbiters[index].angularVelocity = .zero
            }
        }
        orbiters[index].lastDragPosition = newPosition
        orbiters[index].lastDragOrientation = newOrientation
        orbiters[index].lastDragTime = now
    }

    private func beginWeightlessFlight(for index: Int, seedSpin: Bool = false) {
        if seedSpin && !orbiters[index].hasManualOrientation {
            orbiters[index].angularVelocity = orbiters[index].spinAxis * orbiters[index].spinSpeed
        }
        orbiters[index].isFreeFloating = true
        if orbiters[index].isEntering {
            orbiters[index].isEntering = false
            orbiters[index].entryFadeElapsed = modelFadeInDuration
            orbiters[index].hasStartedEntryFade = true
            orbiters[index].entity.components.set(OpacityComponent(opacity: 1))
        }
        orbiters[index].isParked = false
        orbiters[index].parkedBasePosition = nil
        orbiters[index].isReturning = false
        orbiters[index].returnDelay = 0
        orbiters[index].returnEaseElapsed = 0
        orbiters[index].returnStallElapsed = 0.0
        orbiters[index].returnEscapeCooldown = 0.0
        orbiters[index].orientationReturnStart = nil
        orbiters[index].hasManualOrientation = true
    }

    private func advanceFreeFlight(for index: Int, deltaTime: Float) {
        let position = orbiters[index].entity.position
        let distance = simd_length(position)
        let speed = simd_length(orbiters[index].velocity)
        let direction: SIMD3<Float>
        if distance > 0.0001 {
            direction = position / distance
        } else if speed > 0.0001 {
            direction = orbiters[index].velocity / speed
        } else {
            direction = simd_normalize(hoverCenter)
        }

        let speedFactor = min(1.0, speed / 0.9)
        let brakingDistance = min(
            maximumFreeFlightDistance - 0.25,
            freeFlightBrakingDistance + speedFactor * 1.6
        )
        let brakingStart = maximumFreeFlightDistance - brakingDistance
        let brakingProgress = smoothstep(
            (distance - brakingStart) / max(brakingDistance, 0.001)
        )
        let velocityScale = max(0.0, 1.0 - brakingProgress)
        let nextVelocity = orbiters[index].velocity * velocityScale
        let nextPosition = position + nextVelocity * deltaTime

        orbiters[index].lastSafePosition = position
        orbiters[index].releaseVelocity = nextVelocity

        if simd_length(nextPosition) >= maximumFreeFlightDistance {
            orbiters[index].entity.position = direction * maximumFreeFlightDistance
            orbiters[index].velocity = .zero
            orbiters[index].releaseVelocity = .zero
            orbiters[index].returnDelay = 0.0
            orbiters[index].returnEaseElapsed = 0.0
            return
        }

        orbiters[index].velocity = nextVelocity
        orbiters[index].entity.position = nextPosition
        orbiters[index].returnDelay = max(
            0.0,
            orbiters[index].returnDelay - deltaTime
        )
    }

    func endGrab(_ grabbedEntity: Entity, cancelled: Bool = false) {
        guard let index = index(for: grabbedEntity) else { return }
        guard orbiters[index].isGrabbed else { return }
        captureNativeGrabMotion(for: index)
        orbiters[index].isGrabbed = false
        if cancelled {
            // A lost/cancelled pinch is not an intentional throw.
            orbiters[index].releaseVelocity = .zero
            orbiters[index].angularVelocity = .zero
        }

        // Rocky and the activation box now share the same release model:
        // every release enters weightless flight, while only a deliberate
        // throw starts the delayed return. A gentle release is guided back
        // into the ambient orbit instead of snapping or respawning.
        orbiters[index].velocity = orbiters[index].releaseVelocity
        beginWeightlessFlight(for: index)
        let displacement = orbiters[index].grabStartPosition.map {
            simd_distance(orbiters[index].entity.position, $0)
        } ?? 0
        if SpaceModelPhysics.isDeliberateThrow(
            releaseVelocity: orbiters[index].releaseVelocity,
            displacement: displacement
        ) {
            orbiters[index].isReturning = true
            orbiters[index].returnDelay = freeFlightDuration
            orbiters[index].returnDampingDuration = 4.0
        }

        orbiters[index].wasParkedBeforeGrab = false
        orbiters[index].grabStartPosition = nil
        orbiters[index].grabOffset = nil
        orbiters[index].lastDragPosition = nil
        orbiters[index].lastDragOrientation = nil
        orbiters[index].lastDragTime = nil
    }

    func queueModelCollision(
        between firstEntity: Entity,
        and secondEntity: Entity,
        contactPoint: SIMD3<Float>? = nil,
        contactNormal: SIMD3<Float>? = nil,
        penetration: Float = 0
    ) {
        guard let firstIndex = index(for: firstEntity),
              let secondIndex = index(for: secondEntity),
              firstIndex != secondIndex,
              firstEntity === orbiters[firstIndex].entity,
              secondEntity === orbiters[secondIndex].entity,
              orbiters[firstIndex].entryDelayRemaining <= 0.0,
              orbiters[secondIndex].entryDelayRemaining <= 0.0,
              collisionIsInteractionDriven(firstIndex, secondIndex) else { return }

        let lowerIndex = min(firstIndex, secondIndex)
        let upperIndex = max(firstIndex, secondIndex)
        guard !pendingModelCollisions.contains(where: {
            $0.firstIndex == lowerIndex && $0.secondIndex == upperIndex
        }) else { return }

        pendingModelCollisions.append(PendingModelCollision(
            firstIndex: lowerIndex,
            secondIndex: upperIndex,
            contactPoint: contactPoint.map { convert(position: $0, from: nil) },
            contactNormal: contactNormal.map {
                simd_normalize(convert(normal: $0, from: nil))
            },
            penetration: max(0, penetration)
        ))
    }

    private func loadModel(named name: String) async -> Entity? {
        if let entity = try? await Entity(named: name) {
            return entity
        }

        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz"),
              let entity = try? await Entity(contentsOf: url) else {
            return nil
        }

        return entity
    }

    private func generateCompoundCollider(
        from model: Entity,
        relativeTo wrapper: Entity,
        sectionCount: Int
    ) async -> (shapes: [ShapeResource], proxies: [CollisionProxy])? {
        let meshPoints = collectMeshPoints(from: model, relativeTo: wrapper)
        guard meshPoints.count >= 4 else { return nil }

        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for point in meshPoints {
            minimum = simd_min(minimum, point)
            maximum = simd_max(maximum, point)
        }

        let extents = maximum - minimum
        let majorAxis: Int
        if extents.x >= extents.y && extents.x >= extents.z {
            majorAxis = 0
        } else if extents.y >= extents.z {
            majorAxis = 1
        } else {
            majorAxis = 2
        }

        let sectionLength = extents[majorAxis] / Float(sectionCount)
        guard sectionLength > 0.0001 else { return nil }

        var shapes: [ShapeResource] = []
        var proxies: [CollisionProxy] = []
        shapes.reserveCapacity(sectionCount)
        proxies.reserveCapacity(sectionCount)

        for section in 0..<sectionCount {
            let lower = minimum[majorAxis] + Float(section) * sectionLength
            let upper = lower + sectionLength
            let overlap = sectionLength * 0.10
            let sectionPoints = meshPoints.filter { point in
                point[majorAxis] >= lower - overlap
                    && point[majorAxis] <= upper + overlap
            }
            guard sectionPoints.count >= 4 else { continue }

            let reducedPoints = spatiallyReduced(
                sectionPoints,
                maximumCellsPerAxis: 7
            )
            // A flat section has no hull; PhysX would log a cooking error.
            guard reducedPoints.count >= 4,
                  pointsSpanVolume(reducedPoints),
                  let shape = try? await ShapeResource.generateConvex(
                    from: reducedPoints
                  ) else { continue }

            shapes.append(shape)
            proxies.append(collisionProxy(containing: sectionPoints))
        }

        guard shapes.count >= 3, shapes.count == proxies.count else { return nil }
        return (shapes, proxies)
    }

    private func configureInfraredOverlay(in entity: Entity) {
        if let modelEntity = entity as? ModelEntity,
           var modelComponent = modelEntity.model {
            modelComponent.materials = modelComponent.materials.map { _ in
                infraredOverlayMaterial()
            }
            modelEntity.model = modelComponent
        }

        for child in entity.children {
            configureInfraredOverlay(in: child)
        }
    }

    private func disableInteractionComponents(in entity: Entity) {
        entity.components.remove(InputTargetComponent.self)
        entity.components.remove(CollisionComponent.self)
        entity.components.remove(PhysicsBodyComponent.self)
        entity.components.remove(ManipulationComponent.self)
        for child in entity.children {
            disableInteractionComponents(in: child)
        }
    }

    private func infraredOverlayMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(
            red: 1.0,
            green: 0.0,
            blue: 0.025,
            alpha: 1.0
        ))
        material.emissiveColor = .init(color: .black)
        material.emissiveIntensity = 0.0
        material.metallic = 0.0
        material.roughness = 0.45
        material.blending = .transparent(opacity: 1.0)
        return material
    }

    func setInfraredFilterOpacity(_ intensity: Float) {
        let opacity = max(0.0, min(intensity, 1.0)) * 0.04
        for orbiter in orbiters {
            orbiter.infraredOverlay?.components.set(
                OpacityComponent(opacity: opacity)
            )
        }
    }

    private func collectMeshPoints(
        from root: Entity,
        relativeTo wrapper: Entity
    ) -> [SIMD3<Float>] {
        var result: [SIMD3<Float>] = []

        func visit(_ entity: Entity) {
            if let modelComponent = entity.components[ModelComponent.self] {
                let entityTransform = entity.transformMatrix(relativeTo: wrapper)
                let contents = modelComponent.mesh.contents
                var pointsByModel: [String: [SIMD3<Float>]] = [:]

                for meshModel in contents.models {
                    var modelPoints: [SIMD3<Float>] = []
                    for part in meshModel.parts {
                        modelPoints.append(contentsOf: part.positions.elements)
                    }
                    pointsByModel[meshModel.id] = modelPoints
                }

                if contents.instances.isEmpty {
                    for modelPoints in pointsByModel.values {
                        result.append(contentsOf: modelPoints.map {
                            transformPoint($0, by: entityTransform)
                        })
                    }
                } else {
                    for instance in contents.instances {
                        guard let modelPoints = pointsByModel[instance.model] else { continue }
                        let transform = entityTransform * instance.transform
                        result.append(contentsOf: modelPoints.map {
                            transformPoint($0, by: transform)
                        })
                    }
                }
            }

            for child in entity.children {
                visit(child)
            }
        }

        visit(root)
        return result
    }

    private func transformPoint(
        _ point: SIMD3<Float>,
        by transform: simd_float4x4
    ) -> SIMD3<Float> {
        let transformed = transform * SIMD4<Float>(point, 1.0)
        return SIMD3<Float>(transformed.x, transformed.y, transformed.z)
    }

    /// Whether the points enclose volume rather than lying on one plane.
    private func pointsSpanVolume(_ points: [SIMD3<Float>]) -> Bool {
        guard let origin = points.first,
              let far = points.max(by: {
                  simd_length_squared($0 - origin) < simd_length_squared($1 - origin)
              }) else { return false }
        let axis = far - origin
        guard simd_length_squared(axis) > 1e-10,
              let wide = points.max(by: {
                  simd_length_squared(simd_cross(axis, $0 - origin))
                      < simd_length_squared(simd_cross(axis, $1 - origin))
              }) else { return false }
        let normal = simd_cross(axis, wide - origin)
        let normalLength = simd_length(normal)
        guard normalLength > 1e-10 else { return false }
        let unitNormal = normal / normalLength
        let thickness = points.reduce(Float(0)) {
            max($0, abs(simd_dot($1 - origin, unitNormal)))
        }
        return thickness > 0.0005
    }

    private func spatiallyReduced(
        _ points: [SIMD3<Float>],
        maximumCellsPerAxis resolution: Int
    ) -> [SIMD3<Float>] {
        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for point in points {
            minimum = simd_min(minimum, point)
            maximum = simd_max(maximum, point)
        }

        let extents = simd_max(
            maximum - minimum,
            SIMD3<Float>(repeating: 0.000001)
        )
        let center = (minimum + maximum) * 0.5
        var cells: [Int: (point: SIMD3<Float>, distance: Float)] = [:]

        for point in points {
            let normalized = simd_clamp(
                (point - minimum) / extents,
                SIMD3<Float>.zero,
                SIMD3<Float>(repeating: 0.999999)
            )
            let x = Int(normalized.x * Float(resolution))
            let y = Int(normalized.y * Float(resolution))
            let z = Int(normalized.z * Float(resolution))
            let key = x + resolution * (y + resolution * z)
            let distance = simd_length_squared(point - center)
            if cells[key] == nil || distance > cells[key]!.distance {
                cells[key] = (point, distance)
            }
        }

        return cells.values.map(\.point)
    }

    private func collisionProxy(containing points: [SIMD3<Float>]) -> CollisionProxy {
        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for point in points {
            minimum = simd_min(minimum, point)
            maximum = simd_max(maximum, point)
        }
        let center = (minimum + maximum) * 0.5
        let radius = points.reduce(Float.zero) {
            max($0, simd_distance(center, $1))
        }
        return CollisionProxy(center: center, radius: radius)
    }

    private func normalize(_ entity: Entity, targetSize: Float) {
        let bounds = entity.visualBounds(relativeTo: entity)
        let largestDimension = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
        guard largestDimension > 0.0 else { return }

        let scale = targetSize / largestDimension
        entity.scale = SIMD3<Float>(repeating: scale)
    }

    private func orbitalTarget(for orbiter: Orbiter) -> SIMD3<Float> {
        let tilt = orbiter.orbitTiltPhase
        let tiltX = simd_quatf(angle: sin(tilt * 0.71) * 0.95, axis: [1.0, 0.0, 0.0])
        let tiltY = simd_quatf(angle: cos(tilt * 0.53 + 0.8) * 0.85, axis: [0.0, 1.0, 0.0])
        let tiltZ = simd_quatf(angle: sin(tilt * 0.39 + 1.7) * 0.75, axis: [0.0, 0.0, 1.0])
        let layout = orbitLayout(for: orbiter)
        let localCircle = SIMD3<Float>(
            cos(orbiter.orbitPhase) * layout.radius,
            sin(orbiter.orbitVerticalPhase)
                * layout.radius
                * orbiter.orbitVerticalAmplitudeScale,
            sin(orbiter.orbitPhase) * layout.radius * 0.42
        )
        let tiltedCircle = (tiltX * tiltY * tiltZ).act(localCircle)
        let boundedTarget = positionInsideHoverBox(
            layout.center + tiltedCircle,
            inset: orbiter.collisionRadius,
            halfExtents: layout.halfExtents
        )
        return positionInsideComfortableReach(boundedTarget)
    }

    private func separatedOrbitalTarget(for index: Int) -> SIMD3<Float> {
        let orbiter = orbiters[index]
        let baseTarget = orbitalTarget(for: orbiter)

        guard !orbiter.isGrabbed,
              !orbiter.isReturning,
              !orbiter.isParked,
              orbiter.entryDelayRemaining <= 0.0,
              !movieModelsAreHidden else {
            return baseTarget
        }

        var separatedTarget = baseTarget
        for otherIndex in orbiters.indices where otherIndex != index {
            let other = orbiters[otherIndex]
            guard other.entity.isEnabled,
                  other.entryDelayRemaining <= 0.0,
                  !other.isGrabbed else { continue }

            let otherTarget: SIMD3<Float>
            if other.isParked || other.isReturning {
                otherTarget = other.entity.position
            } else {
                otherTarget = orbitalTarget(for: other)
            }

            let separation = separatedTarget - otherTarget
            let distance = simd_length(separation)
            let minimumDistance = max(
                automaticOrbitMinimumSeparation,
                (orbiter.collisionRadius + other.collisionRadius) * 1.35
            )
            guard distance < minimumDistance else { continue }

            let fallbackDirection = orbiter.orbitCenter - other.orbitCenter
            let direction: SIMD3<Float>
            if distance > 0.001 {
                direction = separation / distance
            } else if simd_length_squared(fallbackDirection) > 0.000001 {
                direction = simd_normalize(fallbackDirection)
            } else {
                direction = index < otherIndex
                    ? SIMD3<Float>(-1.0, 0.0, 0.0)
                    : SIMD3<Float>(1.0, 0.0, 0.0)
            }

            separatedTarget += direction
                * (minimumDistance - distance)
                * automaticOrbitSeparationStrength
        }

        let layout = orbitLayout(for: orbiter)
        let boundedTarget = positionInsideHoverBox(
            separatedTarget,
            inset: orbiter.collisionRadius,
            halfExtents: layout.halfExtents
        )
        return positionInsideComfortableReach(boundedTarget)
    }

    private func orbitLayout(
        for orbiter: Orbiter
    ) -> (center: SIMD3<Float>, radius: Float, halfExtents: SIMD3<Float>) {
        (orbiter.orbitCenter, orbiter.orbitRadius, hoverBoxHalfExtents)
    }

    private func horizontalEntryPosition(forRevealIndex index: Int) -> SIMD3<Float> {
        horizontalEntryPosition(
            forRevealIndex: index,
            leadingSide: leadingEntrySide
        )
    }

    private func horizontalEntryPosition(
        forRevealIndex index: Int,
        leadingSide: Float
    ) -> SIMD3<Float> {
        let side = index.isMultiple(of: 2)
            ? leadingSide
            : -leadingSide
        let horizontalDistance = Float.random(in: 1.05...1.25)

        return hoverCenter + SIMD3<Float>(
            side * horizontalDistance,
            Float.random(in: -0.16...0.16),
            Float.random(in: -0.06...0.06)
        )
    }

    private func levelFacingOrigin(from position: SIMD3<Float>) -> simd_quatf {
        let towardViewer = simd_normalize(-position)
        let localZ = -towardViewer
        let worldUp = SIMD3<Float>(0.0, 1.0, 0.0)
        let right = simd_normalize(simd_cross(worldUp, localZ))
        let up = simd_normalize(simd_cross(localZ, right))
        return simd_quatf(simd_float3x3(columns: (right, up, localZ)))
            * simd_quatf(angle: .pi, axis: worldUp)
    }

    private func positionInsideHoverBox(
        _ position: SIMD3<Float>,
        inset: Float,
        halfExtents: SIMD3<Float>? = nil
    ) -> SIMD3<Float> {
        let boxHalfExtents = halfExtents ?? hoverBoxHalfExtents
        let available = boxHalfExtents - SIMD3<Float>(repeating: inset)
        return SIMD3<Float>(
            min(max(position.x, hoverCenter.x - available.x), hoverCenter.x + available.x),
            min(max(position.y, hoverCenter.y - available.y), hoverCenter.y + available.y),
            min(max(position.z, hoverCenter.z - available.z), hoverCenter.z + available.z)
        )
    }

    private func positionInsideComfortableReach(
        _ position: SIMD3<Float>
    ) -> SIMD3<Float> {
        let distance = simd_length(position)
        let fallbackDirection = simd_normalize(hoverCenter)
        let direction = distance > 0.0001
            ? position / distance
            : fallbackDirection

        if distance > comfortableReachMaximum {
            return direction * comfortableReachMaximum
        }
        if distance < comfortableReachMinimum {
            return direction * comfortableReachMinimum
        }
        return position
    }

    private func smoothstep(_ value: Float) -> Float {
        value * value * (3.0 - 2.0 * value)
    }

    private func smootherstep(_ value: Float) -> Float {
        let clamped = min(1.0, max(0.0, value))
        return clamped * clamped * clamped
            * (clamped * (clamped * 6.0 - 15.0) + 10.0)
    }

    private func boxInertia(size: SIMD3<Float>, mass: Float) -> SIMD3<Float> {
        let factor = mass / 12.0
        return SIMD3<Float>(
            factor * (size.y * size.y + size.z * size.z),
            factor * (size.x * size.x + size.z * size.z),
            factor * (size.x * size.x + size.y * size.y)
        )
    }

    private func integrateImpactRotation(for index: Int, deltaTime: Float) {
        guard orbiters[index].hasManualOrientation else { return }
        let angularSpeed = simd_length(orbiters[index].angularVelocity)
        guard angularSpeed > 0.0001 else { return }

        let rotation = simd_quatf(
            angle: angularSpeed * deltaTime,
            axis: orbiters[index].angularVelocity / angularSpeed
        )
        orbiters[index].entity.orientation = simd_normalize(
            rotation * orbiters[index].entity.orientation
        )
    }

    private func setRockyInputEnabled(_ enabled: Bool, for index: Int) {
        guard orbiters[index].inputIsEnabled != enabled else { return }
        orbiters[index].inputIsEnabled = enabled
        let wrapper = orbiters[index].entity
        for entity in [wrapper] + Array(wrapper.children) {
            if var input = entity.components[InputTargetComponent.self] {
                input.isEnabled = enabled
                entity.components.set(input)
            }
        }
    }

    private func naturalManipulation(
        inertia: ManipulationComponent.Dynamics.Inertia = .zero
    ) -> ManipulationComponent {
        var manipulation = ManipulationComponent()
        manipulation.dynamics.translationBehavior = .unconstrained
        manipulation.dynamics.primaryRotationBehavior = .unconstrained
        manipulation.dynamics.secondaryRotationBehavior = .unconstrained
        manipulation.dynamics.scalingBehavior = .none
        manipulation.dynamics.inertia = inertia
        manipulation.releaseBehavior = .stay
        manipulation.audioConfiguration = .none
        return manipulation
    }

    private func keepOrbitersInsideHoverBox() {
        for index in orbiters.indices where !orbiters[index].isGrabbed
            && !orbiters[index].isReturning
            && !orbiters[index].isFreeFloating
            && !orbiters[index].isParked
            && !orbiters[index].isEntering
            && orbiters[index].entryDelayRemaining <= 0.0 {
            let layout = orbitLayout(for: orbiters[index])
            orbiters[index].entity.position = positionInsideHoverBox(
                orbiters[index].entity.position,
                inset: orbiters[index].collisionRadius,
                halfExtents: layout.halfExtents
            )
        }
    }

    private func queueSweptModelCollisions() {
        guard orbiters.count > 1, let scene else { return }
        for firstIndex in 0..<(orbiters.count - 1) {
            let first = orbiters[firstIndex]
            guard first.entity.isEnabled, first.entryDelayRemaining <= 0,
                  first.collisionCooldown == 0 else { continue }
            for secondIndex in (firstIndex + 1)..<orbiters.count {
                let second = orbiters[secondIndex]
                guard second.entity.isEnabled, second.entryDelayRemaining <= 0,
                      second.collisionCooldown == 0,
                      collisionIsInteractionDriven(firstIndex, secondIndex) else { continue }
                // Native contacts also cover resting and initially overlapping
                // shapes. A cast must not invent a contact for such overlaps.
                guard !pendingModelCollisions.contains(where: {
                    $0.firstIndex == firstIndex && $0.secondIndex == secondIndex
                }) else { continue }

                // Broad phase only: including the full rotation-independent
                // radius avoids missing a tip that rotates into another model.
                let firstRadius = first.sweptCollisionProxies.map {
                    simd_length($0.center) + $0.radius
                }.max() ?? first.collisionRadius
                let secondRadius = second.sweptCollisionProxies.map {
                    simd_length($0.center) + $0.radius
                }.max() ?? second.collisionRadius
                guard SpaceModelPhysics.sweepSpheres(
                    firstStart: first.lastSafePosition, firstEnd: first.entity.position,
                    firstRadius: firstRadius,
                    secondStart: second.lastSafePosition, secondEnd: second.entity.position,
                    secondRadius: secondRadius
                ) != nil,
                let firstCollision = first.entity.components[CollisionComponent.self],
                let secondCollision = second.entity.components[CollisionComponent.self] else { continue }

                // Express the first model's motion relative to the moving second
                // model, with the second frozen at its current transform.
                let secondRotation = second.entity.orientation * second.lastSafeOrientation.inverse
                let castStart = second.entity.position
                    + secondRotation.act(first.lastSafePosition - second.lastSafePosition)
                let castStartOrientation = secondRotation * first.lastSafeOrientation
                guard first.collisionHullVertices.count == firstCollision.shapes.count else { continue }
                var earliestProgress: Float = 1.0
                var earliestHit: CollisionCastHit?
                for (shapeIndex, shape) in firstCollision.shapes.enumerated() {
                    let hits = scene.convexCast(
                        convexShape: shape,
                        fromPosition: castStart, fromOrientation: castStartOrientation,
                        toPosition: first.entity.position, toOrientation: first.entity.orientation,
                        query: .all, mask: secondCollision.filter.group, relativeTo: self
                    )
                    for hit in hits where hit.entity === second.entity {
                        guard let progress = SpaceModelPhysics.convexImpactProgress(
                            vertices: first.collisionHullVertices[shapeIndex],
                            fromPosition: castStart, fromOrientation: castStartOrientation,
                            toPosition: first.entity.position, toOrientation: first.entity.orientation,
                            planePoint: hit.position, planeNormal: hit.normal
                        ) else { continue }
                        if earliestHit == nil || progress < earliestProgress {
                            earliestHit = hit
                            earliestProgress = progress
                        }
                    }
                }
                if let hit = earliestHit {
                    // Return the contact from the frozen target pose to its
                    // actual pose at impact, in the orbiter frame of reference.
                    let impactOrientation = simd_slerp(
                        second.lastSafeOrientation, second.entity.orientation, earliestProgress
                    )
                    let backRotation = impactOrientation * second.entity.orientation.inverse
                    let impactPosition = simd_mix(second.lastSafePosition, second.entity.position,
                        SIMD3<Float>(repeating: earliestProgress))
                    let point = impactPosition + backRotation.act(hit.position - second.entity.position)
                    let normal = -backRotation.act(hit.normal)
                    pendingModelCollisions.append(PendingModelCollision(
                        firstIndex: firstIndex, secondIndex: secondIndex,
                        contactPoint: point, contactNormal: normal,
                        sweepProgress: earliestProgress
                    ))
                }
            }
        }
    }

    private func resolvePendingModelCollisions(deltaTime: Float) {
        let collisions = pendingModelCollisions
        pendingModelCollisions.removeAll(keepingCapacity: true)
        for collision in collisions {
            let firstIndex = collision.firstIndex
            let secondIndex = collision.secondIndex
            guard orbiters.indices.contains(firstIndex), orbiters.indices.contains(secondIndex),
                  orbiters[firstIndex].entity.isEnabled, orbiters[secondIndex].entity.isEnabled,
                  orbiters[firstIndex].collisionCooldown == 0,
                  orbiters[secondIndex].collisionCooldown == 0,
                  collisionIsInteractionDriven(firstIndex, secondIndex) else { continue }
            let first = orbiters[firstIndex]
            let second = orbiters[secondIndex]
            let progress = collision.sweepProgress ?? 1
            let firstPosition = simd_mix(first.lastSafePosition, first.entity.position,
                SIMD3<Float>(repeating: progress))
            let secondPosition = simd_mix(second.lastSafePosition, second.entity.position,
                SIMD3<Float>(repeating: progress))
            let separation = secondPosition - firstPosition
            let centerNormal = simd_length_squared(separation) > 0.000001
                ? simd_normalize(separation) : SIMD3<Float>(0, 0, 1)
            var normal = collision.contactNormal ?? centerNormal
            guard simd_length_squared(normal) > 0.000001 else { continue }
            normal = simd_normalize(normal)
            // Sweep normals already have an unambiguous direction at time of impact.
            if collision.sweepProgress == nil && simd_dot(normal, centerNormal) < 0 {
                normal = -normal
            }
            let point = collision.contactPoint ?? firstPosition + normal * first.collisionRadius
            var firstBody = physicsBody(for: first)
            var secondBody = physicsBody(for: second)
            let didBounce = SpaceModelPhysics.resolveContact(
                first: &firstBody, second: &secondBody,
                firstLever: point - firstPosition, secondLever: point - secondPosition,
                normal: normal,
                restitution: first.isMenuOnly || second.isMenuOnly ? SpaceModelPhysics.restitution : 0.08,
                friction: first.isMenuOnly || second.isMenuOnly ? SpaceModelPhysics.friction : 0.32
            )
            let inverseMassSum = firstBody.inverseMass + secondBody.inverseMass
            guard inverseMassSum > 0 else { continue }
            // Resolve overlap without adding kinetic energy or a fixed 4 mm jump.
            let correction = max(0, collision.penetration - 0.0005) * 0.8 / inverseMassSum
            for (index, body, impactPosition, sign) in [
                (firstIndex, firstBody, firstPosition, Float(-1)),
                (secondIndex, secondBody, secondPosition, Float(1))
            ] where !orbiters[index].isGrabbed {
                if didBounce {
                    orbiters[index].velocity = body.velocity
                    orbiters[index].angularVelocity = body.angularVelocity
                    beginCollisionCoast(for: index)
                    if collision.sweepProgress != nil {
                        // Continue the unused part of the frame after impact.
                        orbiters[index].entity.position = impactPosition
                            + body.velocity * deltaTime * (1 - progress)
                    }
                }
                orbiters[index].entity.position += normal * sign * correction * body.inverseMass
            }
            // Separating-velocity checks replace the old 180 ms collision blackout.
        }
    }

    private func physicsBody(for orbiter: Orbiter) -> SpaceModelPhysics.Body {
        SpaceModelPhysics.Body(
            velocity: orbiter.isGrabbed ? orbiter.releaseVelocity : orbiter.velocity,
            angularVelocity: orbiter.angularVelocity,
            inverseMass: orbiter.isGrabbed ? 0 : 1 / orbiter.mass,
            localInertia: orbiter.localInertia,
            orientation: orbiter.entity.orientation
        )
    }

    private func recoverBlockedReturn(for index: Int, target: SIMD3<Float>) {
        let position = orbiters[index].entity.position
        let toTarget = target - position
        let distance = simd_length(toTarget)
        guard distance > returnArrivalDistance else {
            orbiters[index].returnStallElapsed = 0.0
            return
        }

        let direction = toTarget / distance
        let escapeDistance = min(returnEscapeDistance, distance - returnArrivalDistance)
        orbiters[index].entity.position += direction * max(0.0, escapeDistance)

        let escapeSpeed = max(0.12, orbiters[index].travelSpeed * 4.0)
        orbiters[index].velocity = direction * escapeSpeed
        orbiters[index].releaseVelocity = orbiters[index].velocity
        orbiters[index].returnEaseElapsed = orbiters[index].returnDampingDuration
        orbiters[index].returnStallElapsed = 0.0
        orbiters[index].returnEscapeCooldown = returnEscapeCooldownDuration
        // Give the model a short collision-free window to leave the blockage.
        orbiters[index].collisionCooldown = max(
            orbiters[index].collisionCooldown,
            returnEscapeCooldownDuration
        )
        AppTrace.mark(
            "ORBIT return blockage recovered index=\(index) "
                + "distance=\(distance)"
        )
    }

    private func beginCollisionCoast(for index: Int) {
        if orbiters[index].isMenuOnly {
            // Preserve an existing user throw, but never start/restart its timer
            // because of a collision (including on the model that gets hit).
            let wasReturning = orbiters[index].isReturning
            let remainingDelay = orbiters[index].returnDelay
            beginWeightlessFlight(for: index)
            if wasReturning {
                orbiters[index].isReturning = true
                orbiters[index].returnDelay = remainingDelay
                orbiters[index].isFreeFloating = remainingDelay > 0
                orbiters[index].releaseVelocity = orbiters[index].velocity
            }
            return
        }
        orbiters[index].isParked = false
        orbiters[index].wasParkedBeforeGrab = false
        orbiters[index].parkedBasePosition = nil
        orbiters[index].releaseVelocity = orbiters[index].velocity
        orbiters[index].isReturning = true
        orbiters[index].returnDelay = max(orbiters[index].returnDelay, 2.0)
        orbiters[index].returnEaseElapsed = 0.0
        orbiters[index].returnDampingDuration = returnVelocityTransitionDuration
        orbiters[index].orientationReturnStart = nil
        orbiters[index].orientationReturnElapsed = 0.0
        orbiters[index].hasManualOrientation = true
    }

    private func collisionIsInteractionDriven(
        _ firstIndex: Int,
        _ secondIndex: Int
    ) -> Bool {
        guard orbiters.indices.contains(firstIndex),
              orbiters.indices.contains(secondIndex) else { return false }

        // Both hand-driven models may overlap freely. This gate is checked
        // again when resolving queued events, since a grab can start meanwhile.
        guard !(orbiters[firstIndex].isGrabbed && orbiters[secondIndex].isGrabbed) else {
            return false
        }

        return orbiterCarriesInteractiveMomentum(firstIndex)
            || orbiterCarriesInteractiveMomentum(secondIndex)
    }

    private func orbiterCarriesInteractiveMomentum(_ index: Int) -> Bool {
        orbiters[index].isGrabbed
            || orbiters[index].isFreeFloating
            || orbiters[index].isReturning
            || orbiters[index].returnDelay > 0.0
    }

    private func index(for entity: Entity) -> Int? {
        var current: Entity? = entity

        while let candidate = current {
            if let index = orbiters.firstIndex(where: { $0.entity === candidate }) {
                return index
            }

            current = candidate.parent
        }

        return nil
    }

}

@MainActor
final class ActivationBox: Entity {

    private var grabOffset: SIMD3<Float>?
    private let modelPivot = Entity()
    private var signalModel: ModelEntity?
    private var infraredOverlay: Entity?
    private var infraredOpacity = Float.zero
    private var infraredOpacityStart = Float.zero
    private var infraredOpacityTarget = Float.zero
    private var infraredFadeElapsed = Float.zero
    private var activationTarget = false
    private var transitionFromState = false
    private var transitionElapsed: Float?
    private(set) var hasActiveGrab = false

    private let redGlow = SIMD3<Float>(1.0, 0.015, 0.035)
    private let greenGlow = SIMD3<Float>(0.02, 1.0, 0.08)
    private let unlitWhite = SIMD3<Float>(0.58, 0.58, 0.58)
    private let transitionDuration: Float = 0.42
    private let infraredFadeInDuration: Float = 2.0
    private let modelLargestDimension: Float = 0.128

    required init() {
        super.init()
        name = "Petrova Indicator Interactive Object Root"
        modelPivot.name = "Petrova Indicator Model Pivot"
        addChild(modelPivot)
        components.set(OpacityComponent(opacity: 0.0))
    }

    func loadModel() async {
        guard modelPivot.children.isEmpty else { return }

        let model: Entity?
        if let namedModel = try? await Entity(named: "Petrova_Indicator") {
            model = namedModel
        } else if let url = Bundle.main.url(
            forResource: "Petrova_Indicator",
            withExtension: "usdz"
        ) {
            model = try? await Entity(contentsOf: url)
        } else {
            model = nil
        }

        guard let model else { return }

        modelPivot.addChild(model)
        let unscaledBounds = model.visualBounds(relativeTo: modelPivot)
        let largestDimension = max(
            unscaledBounds.extents.x,
            unscaledBounds.extents.y,
            unscaledBounds.extents.z
        )
        if largestDimension > 0.0 {
            model.scale = SIMD3<Float>(
                repeating: modelLargestDimension / largestDimension
            )
        }
        let scaledBounds = model.visualBounds(relativeTo: modelPivot)
        model.position = SIMD3<Float>(
            x: -scaledBounds.center.x,
            y: -scaledBounds.min.y,
            z: -scaledBounds.center.z
        )
        disableInputTargets(in: model)

        signalModel = firstSignalModel(in: model)
        applySignalMaterials(activated: false, glow: 1.0)

        let infraredOverlay = model.clone(recursive: true)
        infraredOverlay.name = "Petrova Indicator Infrared Overlay"
        infraredOverlay.scale *= SIMD3<Float>(repeating: 1.002)
        configureInfraredOverlay(in: infraredOverlay)
        infraredOverlay.components.set(OpacityComponent(opacity: 0.0))
        modelPivot.addChild(infraredOverlay)
        self.infraredOverlay = infraredOverlay

        components.set(InputTargetComponent(allowedInputTypes: .direct))
        components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.08)]))
        components.set(naturalManipulation())

    }

    func contains(_ entity: Entity) -> Bool {
        var candidate: Entity? = entity
        while let current = candidate {
            if current === self { return true }
            candidate = current.parent
        }
        return false
    }

    func beginGrab() {
        hasActiveGrab = true
    }

    func moveGrabbed(to position: SIMD3<Float>) {
        if grabOffset == nil {
            grabOffset = self.position - position
        }
        self.position = position + (grabOffset ?? .zero)
    }

    func endGrab() {
        hasActiveGrab = false
        grabOffset = nil
    }

    func setAstrophageActivated(_ activated: Bool, animated: Bool = true) {
        guard activated != activationTarget else { return }

        if animated, signalModel != nil {
            transitionFromState = activationTarget
            transitionElapsed = 0.0
        } else {
            transitionElapsed = nil
            applySignalMaterials(activated: activated, glow: 1.0)
        }
        activationTarget = activated
    }

    func update(deltaTime: Float) {
        updateInfraredOpacity(deltaTime: deltaTime)

        guard let elapsed = transitionElapsed else { return }

        let nextElapsed = min(transitionDuration, elapsed + deltaTime)
        let progress = smoothstep(nextElapsed / transitionDuration)
        let levels = signalGlowLevels(
            from: transitionFromState,
            to: activationTarget,
            progress: progress
        )
        applySignalMaterials(
            visibleGlowLevel: levels.visible,
            petrovaGlowLevel: levels.petrova
        )

        transitionElapsed = nextElapsed < transitionDuration ? nextElapsed : nil
    }


    private func disableInputTargets(in entity: Entity) {
        entity.components.remove(InputTargetComponent.self)
        for child in entity.children {
            disableInputTargets(in: child)
        }
    }

    private func firstSignalModel(in entity: Entity) -> ModelEntity? {
        if let modelEntity = entity as? ModelEntity,
           (modelEntity.model?.materials.count ?? 0) >= 3 {
            return modelEntity
        }

        for child in entity.children {
            if let signalModel = firstSignalModel(in: child) {
                return signalModel
            }
        }
        return nil
    }

    private func applySignalMaterials(activated: Bool, glow: Float) {
        applySignalMaterials(
            visibleGlowLevel: activated ? 0.0 : glow,
            petrovaGlowLevel: activated ? glow : 0.0
        )
    }

    private func applySignalMaterials(
        visibleGlowLevel: Float,
        petrovaGlowLevel: Float
    ) {
        guard let signalModel,
              var modelComponent = signalModel.model,
              modelComponent.materials.count >= 3 else { return }

        modelComponent.materials[1] = indicatorMaterial(
            glowColor: greenGlow,
            glowLevel: visibleGlowLevel
        )
        modelComponent.materials[2] = indicatorMaterial(
            glowColor: redGlow,
            glowLevel: petrovaGlowLevel
        )
        signalModel.model = modelComponent
    }

    private func signalGlowLevels(
        from previousState: Bool,
        to nextState: Bool,
        progress: Float
    ) -> (visible: Float, petrova: Float) {
        guard previousState != nextState else {
            return nextState ? (0.0, 1.0) : (1.0, 0.0)
        }

        let phase = min(max(progress, 0.0), 1.0) * 2.0
        if previousState {
            return phase < 1.0 ? (0.0, 1.0 - phase) : (phase - 1.0, 0.0)
        } else {
            return phase < 1.0 ? (1.0 - phase, 0.0) : (0.0, phase - 1.0)
        }
    }

    private func configureInfraredOverlay(in entity: Entity) {
        if let modelEntity = entity as? ModelEntity,
           var modelComponent = modelEntity.model {
            modelComponent.materials = modelComponent.materials.map { _ in
                infraredOverlayMaterial()
            }
            modelEntity.model = modelComponent
        }

        for child in entity.children {
            configureInfraredOverlay(in: child)
        }
    }

    func setInfraredFilterOpacity(_ intensity: Float) {
        let target = max(0.0, min(intensity, 1.0)) * 0.04
        guard abs(target - infraredOpacityTarget) > 0.0001 else { return }

        if target < infraredOpacity {
            infraredOpacity = target
            infraredOpacityStart = target
            infraredOpacityTarget = target
            infraredFadeElapsed = 0.0
            infraredOverlay?.components.set(OpacityComponent(opacity: target))
        } else {
            infraredOpacityStart = infraredOpacity
            infraredOpacityTarget = target
            infraredFadeElapsed = 0.0
        }
    }

    private func updateInfraredOpacity(deltaTime: Float) {
        guard infraredOpacity < infraredOpacityTarget else { return }

        infraredFadeElapsed += deltaTime
        let progress = smoothstep(min(1.0, infraredFadeElapsed / infraredFadeInDuration))
        infraredOpacity = infraredOpacityStart
            + (infraredOpacityTarget - infraredOpacityStart) * progress
        infraredOverlay?.components.set(OpacityComponent(opacity: infraredOpacity))
    }

    private func infraredOverlayMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        let infraredRed = UIColor(red: 1.0, green: 0.0, blue: 0.025, alpha: 1.0)
        material.baseColor = .init(tint: infraredRed)
        material.emissiveColor = .init(color: .black)
        material.emissiveIntensity = 0.0
        material.metallic = 0.0
        material.roughness = 0.45
        material.blending = .transparent(opacity: 1.0)
        return material
    }

    private func indicatorMaterial(
        glowColor: SIMD3<Float>,
        glowLevel: Float
    ) -> PhysicallyBasedMaterial {
        let brightness = max(0.0, min(glowLevel, 1.0))
        guard brightness > 0.001 else {
            var offMaterial = PhysicallyBasedMaterial()
            offMaterial.baseColor = .init(tint: UIColor(
                red: CGFloat(unlitWhite.x),
                green: CGFloat(unlitWhite.y),
                blue: CGFloat(unlitWhite.z),
                alpha: 1.0
            ))
            offMaterial.emissiveColor = .init(color: .black)
            offMaterial.emissiveIntensity = 0.0
            offMaterial.metallic = 0.0
            offMaterial.roughness = 1.0
            return offMaterial
        }

        let baseBrightness = 0.08 + 0.92 * brightness
        let tint = UIColor(
            red: CGFloat(glowColor.x * baseBrightness),
            green: CGFloat(glowColor.y * baseBrightness),
            blue: CGFloat(glowColor.z * baseBrightness),
            alpha: 1.0
        )

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: tint)
        material.emissiveColor = .init(color: tint)
        material.emissiveIntensity = 3.5 * brightness
        material.metallic = 0.0
        material.roughness = 0.32
        return material
    }

    private func smoothstep(_ value: Float) -> Float {
        value * value * (3.0 - 2.0 * value)
    }

    private func naturalManipulation() -> ManipulationComponent {
        var manipulation = ManipulationComponent()
        manipulation.dynamics.translationBehavior = .unconstrained
        manipulation.dynamics.primaryRotationBehavior = .unconstrained
        manipulation.dynamics.secondaryRotationBehavior = .unconstrained
        manipulation.dynamics.scalingBehavior = .none
        manipulation.dynamics.inertia = .zero
        manipulation.releaseBehavior = .stay
        manipulation.audioConfiguration = .none
        return manipulation
    }
}
