// Export the exact RealityKit mesh in orbiter coordinates for offline collision cooking.
// swiftc -parse-as-library Tools/ExportRockyCollisionMesh.swift -o /tmp/export-rocky-mesh
// /tmp/export-rocky-mesh "Space Dots/Rockey's Grace-ship.usdz" 0.2646 /tmp/ship.obj
import Foundation
import RealityKit

@main
struct ExportRockyCollisionMesh {
    @MainActor static func main() async throws {
        let arguments = CommandLine.arguments
        precondition(arguments.count == 4, "Usage: export input.usdz targetSize output.obj")
        let model = try await Entity(contentsOf: URL(fileURLWithPath: arguments[1]))
        let targetSize = Float(arguments[2])!
        let bounds = model.visualBounds(relativeTo: model)
        model.scale = SIMD3<Float>(repeating: targetSize / max(bounds.extents.x, bounds.extents.y, bounds.extents.z))
        model.position = -model.visualBounds(relativeTo: model).center
        let wrapper = Entity()
        wrapper.addChild(model)
        var lines: [String] = []
        var vertexCount = 0
        var triangleCount = 0
        func visit(_ entity: Entity) {
            if let component = entity.components[ModelComponent.self] {
                let contents = component.mesh.contents
                let entityTransform = entity.transformMatrix(relativeTo: wrapper)
                func appendModel(_ id: String, transform: simd_float4x4) {
                    guard let mesh = contents.models.first(where: { $0.id == id }) else { return }
                    for part in mesh.parts {
                        let positions = part.positions.elements
                        for point in positions {
                            let p = transform * SIMD4<Float>(point, 1)
                            lines.append("v \(p.x) \(p.y) \(p.z)")
                        }
                        if let triangles = part.triangleIndices?.elements {
                            for i in stride(from: 0, to: triangles.count, by: 3) {
                                lines.append("f \(vertexCount + Int(triangles[i]) + 1) \(vertexCount + Int(triangles[i+1]) + 1) \(vertexCount + Int(triangles[i+2]) + 1)")
                                triangleCount += 1
                            }
                        }
                        vertexCount += positions.count
                    }
                }
                if contents.instances.isEmpty {
                    for mesh in contents.models { appendModel(mesh.id, transform: entityTransform) }
                } else {
                    for instance in contents.instances { appendModel(instance.model, transform: entityTransform * instance.transform) }
                }
            }
            for child in entity.children { visit(child) }
        }
        visit(model)
        try lines.joined(separator: "\n").write(toFile: arguments[3], atomically: true, encoding: .utf8)
        let visual = model.visualBounds(relativeTo: wrapper)
        print("\(arguments[1]): vertices=\(vertexCount) triangles=\(triangleCount) center=\(visual.center) extents=\(visual.extents)")
    }
}
