// Run from the repository root on macOS:
// swiftc -parse-as-library 'Space Dots/RockyMeshCollider.swift' 'Space Dots/SpaceModelPhysics.swift' Tests/RockyColliderChecks.swift -o /tmp/rocky-collider-checks
// /tmp/rocky-collider-checks
import Foundation
import RealityKit
import CryptoKit

@main
struct RockyColliderChecks {
    @MainActor static func main() async throws {
        for (name, targetSize) in [("RockyModelCollision", Float(0.0816)), ("RockyShipCollision", Float(0.2646))] {
            let data = try Data(contentsOf: URL(fileURLWithPath: "Space Dots/\(name).json"))
            let collider = try JSONDecoder().decode(RockyMeshCollider.self, from: data)
            let sourceURL = URL(fileURLWithPath: "Space Dots/\(collider.sourceAsset)")
            let digest = SHA256.hash(data: try Data(contentsOf: sourceURL)).map { String(format: "%02x", $0) }.joined()
            precondition(digest == collider.sourceSHA256, "Source model changed: recook colliders")
            let model = try await Entity(contentsOf: sourceURL)
            let bounds = model.visualBounds(relativeTo: model)
            model.scale = SIMD3<Float>(repeating: targetSize / max(bounds.extents.x, bounds.extents.y, bounds.extents.z))
            model.position = -model.visualBounds(relativeTo: model).center
            let wrapper = Entity()
            wrapper.addChild(model)
            let start = Date()
            let shapes = try await collider.makeShapes(matching: model.visualBounds(relativeTo: wrapper))
            precondition(shapes.count == collider.hulls.count && shapes.count > 10)
            print("PASS: \(name), \(shapes.count) native convex shapes, source hash and transformed bounds match; cook \(Date().timeIntervalSince(start))s")
            if name == "RockyShipCollision" {
                let view = ARView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
                let anchor = AnchorEntity(world: .zero)
                let target = Entity()
                let group = CollisionGroup(rawValue: 1 << 9)
                target.components.set(CollisionComponent(shapes: shapes,
                    filter: CollisionFilter(group: group, mask: .all)))
                target.components.set(PhysicsBodyComponent(shapes: shapes, mass: 5.2, mode: .kinematic))
                let grabTarget = Entity()
                grabTarget.components.set(CollisionComponent(shapes: [.generateBox(size: [0.35, 0.1, 0.2])],
                    mode: .trigger, filter: CollisionFilter(group: CollisionGroup(rawValue: 1 << 30), mask: [])))
                target.addChild(grabTarget)
                anchor.addChild(target)
                view.scene.addAnchor(anchor)
                try await Task.sleep(for: .milliseconds(100))
                let probeSize: Float = 0.004
                let probe = ShapeResource.generateBox(size: SIMD3<Float>(repeating: probeSize))
                let identity = simd_quatf(angle: 0, axis: [0, 1, 0])
                var probeVertices: [SIMD3<Float>] = []
                for x: Float in [-1, 1] { for y: Float in [-1, 1] { for z: Float in [-1, 1] {
                    probeVertices.append(SIMD3<Float>(x, y, z) * probeSize * 0.5)
                } } }
                for (x, z, expectedHit): (Float, Float, Bool) in [
                    (-0.0236, 0.0180, false), (-0.0326, 0, false), (0.0754, 0, false),
                    (0.0844, -0.0567, true), (-0.0866, 0.0675, true)
                ] {
                    let from = SIMD3<Float>(x, 0.15, z)
                    let to = SIMD3<Float>(x, -0.15, z)
                    let hits = view.scene.convexCast(convexShape: probe,
                        fromPosition: from, fromOrientation: identity,
                        toPosition: to, toOrientation: identity,
                        query: .all, mask: group, relativeTo: anchor)
                    precondition(!hits.isEmpty == expectedHit, "Wrong ship contact at \(x), \(z)")
                    precondition(hits.allSatisfy { $0.entity === target }, "Grab target entered physical query")
                    if let hit = hits.first {
                        let progress = SpaceModelPhysics.convexImpactProgress(vertices: probeVertices,
                            fromPosition: from, fromOrientation: identity,
                            toPosition: to, toOrientation: identity,
                            planePoint: hit.position, planeNormal: hit.normal)!
                        let center = simd_mix(from, to, SIMD3<Float>(repeating: progress))
                        let gap = probeVertices.map { simd_dot(center + $0 - hit.position, hit.normal) }.min()!
                        precondition(abs(gap) < 0.0001, "Sweep stopped beyond the actual contact plane")
                    }
                }
                print("PASS: native convex casts pass through 3 empty ship gaps, hit 2 structural parts, ignore the grab box, and recover contact time")
            }
            do {
                _ = try await collider.makeShapes(matching: BoundingBox(min: .zero, max: [1, 1, 1]))
                preconditionFailure("Mismatched geometry was accepted")
            } catch RockyMeshCollider.LoadError.mismatchedBounds { }
        }
    }
}
