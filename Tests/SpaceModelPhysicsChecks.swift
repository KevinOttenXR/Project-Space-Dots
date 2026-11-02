// Run from the repository root:
// swiftc 'Space Dots/SpaceModelPhysics.swift' Tests/SpaceModelPhysicsChecks.swift -o /tmp/space-model-physics-checks && /tmp/space-model-physics-checks
import Foundation
import simd

@main
struct SpaceModelPhysicsChecks {
    static func close(_ a: SIMD3<Float>, _ b: SIMD3<Float>, tolerance: Float = 0.0001) {
        precondition(simd_distance(a, b) < tolerance, "Expected \(b), got \(a)")
    }

    static func body(mass: Float = 1, velocity: SIMD3<Float> = .zero) -> SpaceModelPhysics.Body {
        SpaceModelPhysics.Body(velocity: velocity, angularVelocity: .zero,
            inverseMass: 1 / mass, localInertia: SIMD3<Float>(repeating: mass / 6),
            orientation: simd_quatf(angle: 0, axis: [0, 1, 0]))
    }

    static func energy(_ body: SpaceModelPhysics.Body) -> Float {
        let localSpin = body.orientation.inverse.act(body.angularVelocity)
        return 0.5 * simd_length_squared(body.velocity) / body.inverseMass
            + 0.5 * simd_dot(localSpin * body.localInertia, localSpin)
    }

    static func main() {
        // Equal-mass elastic collision swaps velocities exactly.
        var first = body(velocity: [1, 0, 0])
        var second = body()
        precondition(SpaceModelPhysics.resolveContact(first: &first, second: &second,
            firstLever: [0.5, 0, 0], secondLever: [-0.5, 0, 0], normal: [1, 0, 0],
            restitution: 1, friction: 0))
        close(first.velocity, .zero)
        close(second.velocity, [1, 0, 0])

        // Unequal masses and an off-centre strike conserve linear AND angular
        // momentum while dissipating, rather than creating, kinetic energy.
        first = body(mass: 2.4, velocity: [0.7, 0.2, 0])
        second = body(mass: 5.2)
        let initialMomentum = first.velocity * 2.4 + second.velocity * 5.2
        let initialEnergy = energy(first) + energy(second)
        let firstPosition = SIMD3<Float>(-0.5, 0, 0)
        let secondPosition = SIMD3<Float>(0.5, 0, 0)
        let contact = SIMD3<Float>(0, 0.3, 0)
        let initialAngularMomentum = simd_cross(firstPosition, first.velocity * 2.4)
        precondition(SpaceModelPhysics.resolveContact(first: &first, second: &second,
            firstLever: contact - firstPosition, secondLever: contact - secondPosition,
            normal: [1, 0, 0]))
        close(first.velocity * 2.4 + second.velocity * 5.2, initialMomentum)
        let angularMomentum = simd_cross(firstPosition, first.velocity * 2.4)
            + simd_cross(secondPosition, second.velocity * 5.2)
            + first.angularVelocity * first.localInertia
            + second.angularVelocity * second.localInertia
        close(angularMomentum, initialAngularMomentum)
        precondition(energy(first) + energy(second) <= initialEnergy + 0.0001)
        precondition(simd_length(first.angularVelocity) > 0.01)
        precondition(simd_length(second.angularVelocity) > 0.01)

        // A separating pair must not get a second impulse on the next frame.
        first = body(velocity: [-0.1, 0, 0])
        second = body(velocity: [0.1, 0, 0])
        precondition(!SpaceModelPhysics.resolveContact(first: &first, second: &second,
            firstLever: .zero, secondLever: .zero, normal: [1, 0, 0]))
        close(first.velocity, [-0.1, 0, 0])

        // Both hand-driven bodies remain unchanged, including their spin.
        first = body(velocity: [1, 0, 0])
        second = body(velocity: [-1, 0, 0])
        first = SpaceModelPhysics.Body(velocity: first.velocity, angularVelocity: [0, 1, 0],
            inverseMass: 0, localInertia: first.localInertia, orientation: first.orientation)
        second = SpaceModelPhysics.Body(velocity: second.velocity, angularVelocity: [1, 0, 0],
            inverseMass: 0, localInertia: second.localInertia, orientation: second.orientation)
        precondition(!SpaceModelPhysics.resolveContact(first: &first, second: &second,
            firstLever: [0.5, 0, 0], secondLever: [-0.5, 0, 0], normal: [1, 0, 0]))
        close(first.velocity, [1, 0, 0])
        close(second.velocity, [-1, 0, 0])
        close(first.angularVelocity, [0, 1, 0])

        // Rotating a held model can impart contact velocity to a free model.
        second = body()
        precondition(SpaceModelPhysics.resolveContact(first: &first, second: &second,
            firstLever: [0, 0, 0.5], secondLever: [-0.5, 0, 0], normal: [1, 0, 0]))
        close(first.velocity, [1, 0, 0])
        precondition(second.velocity.x > 0)

        // Fast crossings hit on the near side, and misses stay misses.
        let hit = SpaceModelPhysics.sweepSpheres(
            firstStart: [-1, 0, 0], firstEnd: [1, 0, 0], firstRadius: 0.1,
            secondStart: .zero, secondEnd: .zero, secondRadius: 0.1)!
        precondition(abs(hit.progress - 0.4) < 0.0001)
        close(hit.normal, [1, 0, 0])
        close(hit.point, [-0.1, 0, 0])
        precondition(SpaceModelPhysics.sweepSpheres(
            firstStart: [-1, 0.3, 0], firstEnd: [1, 0.3, 0], firstRadius: 0.1,
            secondStart: .zero, secondEnd: .zero, secondRadius: 0.1) == nil)
        let overlap = SpaceModelPhysics.sweepSpheres(
            firstStart: .zero, firstEnd: .zero, firstRadius: 0.1,
            secondStart: [0.1, 0, 0], secondEnd: [0.1, 0, 0], secondRadius: 0.1)!
        precondition(abs(overlap.penetration - 0.1) < 0.0001)

        // Torque samples handle quaternion sign changes without a spin spike.
        let rotation = simd_quatf(angle: 0.2, axis: [0, 1, 0])
        close(SpaceModelPhysics.angularVelocity(from: simd_quatf(angle: 0, axis: [0, 1, 0]), to: rotation, elapsed: 0.1), [0, 2, 0])
        close(SpaceModelPhysics.angularVelocity(from: rotation,
            to: simd_quatf(vector: -rotation.vector), elapsed: 0.01), .zero)

        // No frame-based braking in open space; compare boundary integration
        // over equal real time at headset/simulator refresh rates.
        var results: [SIMD3<Float>] = []
        for fps in [30, 60, 90, 120] {
            var position = SIMD3<Float>(0, 0, -0.7)
            var velocity = SIMD3<Float>(0.1, 0, 0)
            for _ in 0..<fps { SpaceModelPhysics.advanceFlight(position: &position, velocity: &velocity, deltaTime: 1 / Float(fps)) }
            close(velocity, [0.1, 0, 0])
            close(position, [0.1, 0, -0.7])
            position = [0, 0, -2]
            velocity = [0.1, 0, -1]
            for _ in 0..<(fps * 8) { SpaceModelPhysics.advanceFlight(position: &position, velocity: &velocity, deltaTime: 1 / Float(fps)) }
            precondition(simd_length(position) < 3)
            results.append(position)
        }
        for position in results { close(position, results[0], tolerance: 0.015) }

        precondition(SpaceModelPhysics.isDeliberateThrow(releaseVelocity: [0.8, 0, 0], displacement: 0.2))
        precondition(!SpaceModelPhysics.isDeliberateThrow(releaseVelocity: [0.1, 0, 0], displacement: 0.2))
        precondition(!SpaceModelPhysics.isDeliberateThrow(releaseVelocity: [0.8, 0, 0], displacement: 0.01))
        print("PASS: momentum, energy, glancing impact/spin, separating contacts, held models, sweeps, release rotation, frame rates, and deliberate-throw classification")
    }
}
