import Foundation
import simd

/// Shared math for the manually integrated, kinematic space models.
/// Keeping this independent of RealityKit also allows deterministic physics checks.
enum SpaceModelPhysics {
    static let restitution: Float = 0.62
    static let friction: Float = 0.12
    static let rotationalInertiaMultiplier: Float = 1.35

    // Slow placement, a rotation in place, and tracking jitter are not throws.
    // Called only when a model that the user actually grabbed is released.
    static func isDeliberateThrow(
        releaseVelocity: SIMD3<Float>, displacement: Float
    ) -> Bool {
        simd_length(releaseVelocity) >= 0.45 && displacement >= 0.05
    }

    struct Body {
        var velocity: SIMD3<Float>
        var angularVelocity: SIMD3<Float>
        let inverseMass: Float
        let localInertia: SIMD3<Float>
        let orientation: simd_quatf

        func inverseInertia(_ vector: SIMD3<Float>) -> SIMD3<Float> {
            guard inverseMass > 0 else { return .zero }
            return orientation.act(
                orientation.inverse.act(vector)
                    / simd_max(localInertia, SIMD3<Float>(repeating: 0.000001))
            )
        }

        func contactVelocity(at lever: SIMD3<Float>) -> SIMD3<Float> {
            velocity + simd_cross(angularVelocity, lever)
        }

        mutating func apply(_ impulse: SIMD3<Float>, at lever: SIMD3<Float>) {
            velocity += impulse * inverseMass
            angularVelocity += inverseInertia(simd_cross(lever, impulse))
        }
    }

    /// Normal points from the first body towards the second body.
    /// Returns false for separating/resting contacts; these must never receive a bounce.
    @discardableResult
    static func resolveContact(
        first: inout Body,
        second: inout Body,
        firstLever: SIMD3<Float>,
        secondLever: SIMD3<Float>,
        normal: SIMD3<Float>,
        restitution: Float = restitution,
        friction: Float = friction
    ) -> Bool {
        let relativeVelocity = first.contactVelocity(at: firstLever)
            - second.contactVelocity(at: secondLever)
        let approachSpeed = simd_dot(relativeVelocity, normal)
        guard approachSpeed > 0.0001 else { return false }

        func effectiveMass(along direction: SIMD3<Float>) -> Float {
            first.inverseMass + second.inverseMass + max(0, simd_dot(direction,
                simd_cross(first.inverseInertia(simd_cross(firstLever, direction)), firstLever)
                    + simd_cross(second.inverseInertia(simd_cross(secondLever, direction)), secondLever)
            ))
        }

        let denominator = effectiveMass(along: normal)
        guard denominator > 0.000001 else { return false }
        // Suppress restitution only for near-resting contact to avoid chatter.
        let bounce = approachSpeed > 0.005 ? restitution : 0
        let normalMagnitude = (1 + bounce) * approachSpeed / denominator
        let normalImpulse = normal * normalMagnitude
        first.apply(-normalImpulse, at: firstLever)
        second.apply(normalImpulse, at: secondLever)

        // Evaluate friction AFTER the normal impulse, which can itself induce spin.
        let residualVelocity = first.contactVelocity(at: firstLever)
            - second.contactVelocity(at: secondLever)
        let tangentVelocity = residualVelocity - normal * simd_dot(residualVelocity, normal)
        let tangentSpeed = simd_length(tangentVelocity)
        if tangentSpeed > 0.0001 {
            let tangent = tangentVelocity / tangentSpeed
            let tangentDenominator = effectiveMass(along: tangent)
            if tangentDenominator > 0.000001 {
                let frictionImpulse = tangent * min(
                    tangentSpeed / tangentDenominator, normalMagnitude * friction
                )
                first.apply(-frictionImpulse, at: firstLever)
                second.apply(frictionImpulse, at: secondLever)
            }
        }
        return true
    }

    static func angularVelocity(
        from previous: simd_quatf,
        to current: simd_quatf,
        elapsed: Float
    ) -> SIMD3<Float> {
        guard elapsed > 0.0001 else { return .zero }
        var delta = simd_normalize(current * previous.inverse)
        // q and -q represent the same orientation; always take the shorter arc.
        if delta.real < 0 { delta = simd_quatf(vector: -delta.vector) }
        let sine = simd_length(delta.imag)
        guard sine > 0.000001 else { return .zero }
        return delta.imag / sine * (2 * atan2(sine, delta.real) / elapsed)
    }

    /// No drag in the interaction area. A soft radial force outside it keeps
    /// thrown props discoverable without a timed return or a position snap.
    static func advanceFlight(
        position: inout SIMD3<Float>,
        velocity: inout SIMD3<Float>,
        deltaTime: Float,
        freeRadius: Float = 2.15
    ) {
        guard deltaTime > 0, deltaTime.isFinite else { return }
        let steps = max(1, Int(ceil(min(deltaTime, 0.1) * 120)))
        let dt = min(deltaTime, 0.1) / Float(steps)
        for _ in 0..<steps {
            let distance = simd_length(position)
            if distance > freeRadius {
                let radialDirection = position / distance
                let outwardSpeed = max(0, simd_dot(velocity, radialDirection))
                let penetration = distance - freeRadius
                let engagement = min(1, penetration / 0.7)
                velocity -= radialDirection
                    * (0.65 * penetration + 1.6 * engagement * outwardSpeed) * dt
            }
            position += velocity * dt
        }
    }

    struct SweepContact {
        let progress: Float
        let normal: SIMD3<Float>
        let point: SIMD3<Float>
        let penetration: Float
    }

    /// Recover time of impact from the hull's support point and the contact
    /// plane. A cast hit's point/distance is not the moving body's origin;
    /// dividing that distance by origin travel can place the body past impact.
    static func convexImpactProgress(
        vertices: [SIMD3<Float>],
        fromPosition: SIMD3<Float>, fromOrientation: simd_quatf,
        toPosition: SIMD3<Float>, toOrientation: simd_quatf,
        planePoint: SIMD3<Float>, planeNormal: SIMD3<Float>
    ) -> Float? {
        guard !vertices.isEmpty else { return nil }
        func gap(at progress: Float) -> Float {
            let rotation = simd_slerp(fromOrientation, toOrientation, progress)
            let localNormal = rotation.inverse.act(planeNormal)
            let support = vertices.map { simd_dot($0, localNormal) }.min()!
            let position = simd_mix(fromPosition, toPosition, SIMD3<Float>(repeating: progress))
            return support + simd_dot(position - planePoint, planeNormal)
        }
        // Initial overlaps use native contact points and penetration instead.
        guard gap(at: 0) > 0.00001 else { return nil }
        var lower: Float = 0
        for step in 1...8 {
            var upper = Float(step) / 8
            if gap(at: upper) <= 0 {
                for _ in 0..<12 {
                    let middle = (lower + upper) * 0.5
                    if gap(at: middle) > 0 { lower = middle } else { upper = middle }
                }
                return upper
            }
            lower = upper
        }
        return nil
    }

    /// First time of impact, rather than closest approach (which may already
    /// be on the far side of the other model).
    static func sweepSpheres(
        firstStart: SIMD3<Float>, firstEnd: SIMD3<Float>, firstRadius: Float,
        secondStart: SIMD3<Float>, secondEnd: SIMD3<Float>, secondRadius: Float
    ) -> SweepContact? {
        let separation = secondStart - firstStart
        let travel = (secondEnd - secondStart) - (firstEnd - firstStart)
        let radius = firstRadius + secondRadius
        let c = simd_length_squared(separation) - radius * radius
        let progress: Float
        if c <= 0 {
            progress = 0
        } else {
            let a = simd_length_squared(travel)
            let b = simd_dot(separation, travel)
            let discriminant = b * b - a * c
            guard a > 0.00000001, b < 0, discriminant >= 0 else { return nil }
            progress = (-b - sqrt(discriminant)) / a
            guard progress >= 0, progress <= 1 else { return nil }
        }
        let contactSeparation = separation + travel * progress
        let distance = simd_length(contactSeparation)
        let normal = distance > 0.00001 ? contactSeparation / distance
            : (simd_length_squared(travel) > 0.00000001
                ? -simd_normalize(travel) : SIMD3<Float>(1, 0, 0))
        let firstCenter = firstStart + (firstEnd - firstStart) * progress
        let penetration = max(0, radius - distance)
        return SweepContact(
            progress: progress,
            normal: normal,
            point: firstCenter + normal * (firstRadius - penetration * 0.5),
            penetration: penetration
        )
    }
}
