import Foundation
import RealityKit

/// Offline convex decomposition of the actual USDZ mesh, in orbiter coordinates.
/// Triangle meshes cannot be attached to moving RealityKit physics bodies.
struct RockyMeshCollider: Decodable {
    struct Hull: Decodable {
        let vertices: [[Float]]
        let triangles: [[Int]]
    }
    let version: Int
    let sourceAsset: String
    let sourceSHA256: String
    let toleranceMetres: Float
    let boundsMinimum: [Float]
    let boundsMaximum: [Float]
    let hulls: [Hull]

    enum LoadError: Error { case missingAsset, invalidGeometry, mismatchedBounds }

    @MainActor
    static func load(named name: String, bounds: BoundingBox) async throws
        -> (shapes: [ShapeResource], vertices: [[SIMD3<Float>]]) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw LoadError.missingAsset
        }
        let collider = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        let shapes = try await collider.makeShapes(matching: bounds)
        let vertices = collider.hulls.map { $0.vertices.map { SIMD3<Float>($0[0], $0[1], $0[2]) } }
        return (shapes, vertices)
    }

    @MainActor
    func makeShapes(matching bounds: BoundingBox) async throws -> [ShapeResource] {
        guard version == 1, !hulls.isEmpty, hulls.count <= 512,
              boundsMinimum.count == 3, boundsMaximum.count == 3 else {
            throw LoadError.invalidGeometry
        }
        let minimum = SIMD3<Float>(boundsMinimum[0], boundsMinimum[1], boundsMinimum[2])
        let maximum = SIMD3<Float>(boundsMaximum[0], boundsMaximum[1], boundsMaximum[2])
        guard simd_distance(minimum, bounds.min) < 0.0001,
              simd_distance(maximum, bounds.max) < 0.0001 else {
            throw LoadError.mismatchedBounds
        }
        let verticesByHull = try hulls.map { hull -> [SIMD3<Float>] in
            guard (4...64).contains(hull.vertices.count),
                  hull.vertices.allSatisfy({ $0.count == 3 && $0.allSatisfy(\.isFinite) }) else {
                throw LoadError.invalidGeometry
            }
            return hull.vertices.map { SIMD3<Float>($0[0], $0[1], $0[2]) }
        }
        // Bound concurrency so mesh cooking doesn't serially delay the reveal
        // or flood the headset's worker pool with hundreds of jobs at once.
        var shapes: [ShapeResource] = []
        for start in stride(from: 0, to: verticesByHull.count, by: 8) {
            let batch = try await withThrowingTaskGroup(of: (Int, ShapeResource).self) { group in
                for index in start..<min(start + 8, verticesByHull.count) {
                    let vertices = verticesByHull[index]
                    group.addTask { (index, try await ShapeResource.generateConvex(from: vertices)) }
                }
                var result: [(Int, ShapeResource)] = []
                for try await shape in group { result.append(shape) }
                return result.sorted { $0.0 < $1.0 }.map(\.1)
            }
            shapes.append(contentsOf: batch)
        }
        return shapes
    }
}
