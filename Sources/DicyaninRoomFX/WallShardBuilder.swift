//
//  WallShardBuilder.swift
//  DicyaninRoomFX
//
//  Cuts the region around a crack pattern into wedge-shaped wall shards
//  (extruded prisms) that fly out when the wall opens. Shards are cut along the
//  pattern's primary crack directions so debris matches the visible cracks.
//

import Foundation
import RealityKit
import simd

/// One wall shard: a prism wedge between two crack directions.
public struct WallShard: Sendable {
    /// Wall-plane vertices of the wedge outline (fan around the impact point).
    public var outline: [SIMD2<Float>]
    /// Wall-plane centroid, used to position the shard entity.
    public var centroid: SIMD2<Float>
    /// Unit direction from the impact point through the centroid.
    public var outwardDirection: SIMD2<Float>
}

/// Builds shard layouts and shard entities for a crack pattern.
@MainActor
public enum WallShardBuilder {

    /// Splits the disc around the impact into wedges along the pattern's
    /// primary crack directions. Pure logic, deterministic, testable.
    public static func shards(for pattern: CrackPattern) -> [WallShard] {
        var angles = pattern.primaryDirections.map { atan2($0.y, $0.x) }.sorted()
        guard angles.count >= 2 else { return [] }
        angles.append(angles[0] + 2 * .pi)

        var rng = RoomFXRandom(seed: pattern.seed ^ 0xD1CE)
        var shards: [WallShard] = []
        for i in 0..<(angles.count - 1) {
            let a0 = angles[i], a1 = angles[i + 1]
            guard a1 - a0 > 0.12 else { continue }
            // Jagged outer arc between the two crack edges.
            var outline: [SIMD2<Float>] = [.zero]
            let arcSteps = max(2, Int((a1 - a0) / 0.35))
            for step in 0...arcSteps {
                let t = Float(step) / Float(arcSteps)
                let angle = a0 + (a1 - a0) * t
                let radius = pattern.radius * rng.float(in: 0.75...1.0)
                outline.append(SIMD2<Float>(cos(angle), sin(angle)) * radius)
            }
            let centroid = outline.reduce(SIMD2<Float>.zero, +) / Float(outline.count)
            let mid = (a0 + a1) * 0.5
            shards.append(WallShard(outline: outline,
                                    centroid: centroid,
                                    outwardDirection: SIMD2<Float>(cos(mid), sin(mid))))
        }
        return shards
    }

    /// Builds a `ModelEntity` prism for one shard, positioned at its centroid in
    /// the wall plane (XY, +Z out of the wall).
    public static func makeEntity(for shard: WallShard,
                                  configuration: RoomFXConfiguration,
                                  material: RealityKit.Material) -> ModelEntity? {
        let local = shard.outline.map { $0 - shard.centroid }
        guard let mesh = prismMesh(outline: local, thickness: configuration.shardThickness) else {
            return nil
        }
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "RoomFX.WallShard"
        entity.position = SIMD3<Float>(shard.centroid.x, shard.centroid.y, 0)

        let bounds = entity.visualBounds(relativeTo: entity)
        let shape = ShapeResource.generateBox(size: max(bounds.extents, SIMD3<Float>(repeating: 0.01)))
        entity.collision = CollisionComponent(shapes: [shape])

        if configuration.physicsMode == .physics {
            var body = PhysicsBodyComponent(massProperties: .init(mass: 1.5),
                                            material: .generate(friction: 0.7, restitution: 0.1),
                                            mode: .dynamic)
            body.isAffectedByGravity = true
            entity.components.set(body)
        }
        return entity
    }

    /// Extrudes a fan-triangulated 2D outline into a prism (front, back, sides).
    static func prismMesh(outline: [SIMD2<Float>], thickness: Float) -> MeshResource? {
        guard outline.count >= 3 else { return nil }
        let half = thickness / 2
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let n = outline.count

        // Front (+Z) and back (-Z) rings.
        for p in outline { positions.append(SIMD3<Float>(p.x, p.y, half)); normals.append(SIMD3<Float>(0, 0, 1)) }
        for p in outline { positions.append(SIMD3<Float>(p.x, p.y, -half)); normals.append(SIMD3<Float>(0, 0, -1)) }

        // Fan triangulation of front and back caps.
        for i in 1..<(n - 1) {
            indices.append(contentsOf: [0, UInt32(i), UInt32(i + 1)])
            indices.append(contentsOf: [UInt32(n), UInt32(n + i + 1), UInt32(n + i)])
        }

        // Side walls with their own flat-shaded vertices.
        for i in 0..<n {
            let j = (i + 1) % n
            let a = outline[i], b = outline[j]
            var edgeNormal = SIMD2<Float>(b.y - a.y, a.x - b.x)
            if simd_length(edgeNormal) < 1e-6 { continue }
            edgeNormal = simd_normalize(edgeNormal)
            let normal = SIMD3<Float>(edgeNormal.x, edgeNormal.y, 0)
            let base = UInt32(positions.count)
            positions.append(contentsOf: [SIMD3<Float>(a.x, a.y, half),
                                          SIMD3<Float>(b.x, b.y, half),
                                          SIMD3<Float>(b.x, b.y, -half),
                                          SIMD3<Float>(a.x, a.y, -half)])
            normals.append(contentsOf: [normal, normal, normal, normal])
            indices.append(contentsOf: [base, base + 1, base + 2,
                                        base, base + 2, base + 3])
        }

        var descriptor = MeshDescriptor(name: "wallShard")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
