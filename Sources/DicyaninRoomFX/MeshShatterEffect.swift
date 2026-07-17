//
//  MeshShatterEffect.swift
//  DicyaninRoomFX
//
//  Shatters a reconstructed scene-mesh chunk along its real geometry: reads the
//  MeshAnchor's actual triangles, clusters them spatially into shards, and
//  spawns each shard as its own entity with physics (or animated fallout).
//

import ARKit
import Foundation
import RealityKit
import simd
import DicyaninSceneReconstruction

/// Shatters real scanned geometry into flying pieces.
@MainActor
public enum MeshShatterEffect {

    /// A shard cut from the real mesh: triangle soup in anchor-local space.
    struct Shard {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var centroid: SIMD3<Float> = .zero
    }

    /// Shatters `anchor`'s geometry into roughly ``RoomFXConfiguration/shatterPieceCount``
    /// shards and returns the root entity containing them (already placed at
    /// the anchor's world transform). Add it to your scene, and hide or remove
    /// the original chunk entity yourself.
    ///
    /// - Parameters:
    ///   - anchor: The scene-reconstruction mesh anchor to shatter.
    ///   - impactPoint: Optional world-space impact; shards fly away from it.
    ///   - configuration: Physics mode, piece count, impulse, lifetime.
    /// - Returns: Root entity with one child per shard, or `nil` if the anchor
    ///   has no readable geometry. Must be called on the main queue.
    public static func shatter(anchor: MeshAnchor,
                               impactPoint: SIMD3<Float>? = nil,
                               configuration: RoomFXConfiguration) -> Entity? {
        let geometry = anchor.geometry
        let vertices = geometry.vertices.asSIMD3(ofType: Float.self)
        let faceCount = geometry.faces.count
        guard !vertices.isEmpty, faceCount > 0 else { return nil }

        let indexPointer = geometry.faces.buffer.contents()
            .bindMemory(to: UInt32.self, capacity: faceCount * 3)

        let shards = cluster(vertices: vertices,
                             indexPointer: indexPointer,
                             faceCount: faceCount,
                             pieceCount: max(configuration.shatterPieceCount, 2))
        guard !shards.isEmpty else { return nil }

        let root = Entity()
        root.name = "RoomFX.Shatter"
        root.transform = Transform(matrix: anchor.originFromAnchorTransform)

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: RoomFXColor(white: 0.75, alpha: 1))
        material.roughness = .init(floatLiteral: 0.95)

        var rng = RoomFXRandom(seed: CrackGenerator.seed(for: root.position) ^ 0x5A77)
        let localImpact: SIMD3<Float>? = impactPoint.map {
            root.convert(position: $0, from: nil)
        }

        for shard in shards {
            guard let entity = makeShardEntity(shard: shard,
                                               material: material,
                                               configuration: configuration) else { continue }
            root.addChild(entity)
            applyMotion(to: entity, shard: shard, localImpact: localImpact,
                        root: root, configuration: configuration, rng: &rng)
        }

        // Auto-cleanup after the debris lifetime.
        Task {
            try? await Task.sleep(nanoseconds: UInt64(configuration.debrisLifetime * 1e9))
            root.removeFromParent()
        }
        return root
    }

    /// Groups faces into shards by snapping face centroids to a spatial grid
    /// sized to yield about `pieceCount` occupied cells: shards follow the real
    /// surface, so breakage lines run along actual room geometry.
    static func cluster(vertices: [SIMD3<Float>],
                        indexPointer: UnsafePointer<UInt32>,
                        faceCount: Int,
                        pieceCount: Int) -> [Shard] {
        var minBound = vertices[0], maxBound = vertices[0]
        for v in vertices { minBound = simd_min(minBound, v); maxBound = simd_max(maxBound, v) }
        let size = simd_max(maxBound - minBound, SIMD3<Float>(repeating: 0.01))
        let volume = size.x * size.y * size.z
        let cell = max(cbrt(volume / Float(pieceCount)), 0.05)

        var cells: [SIMD3<Int32>: Shard] = [:]
        for face in 0..<faceCount {
            let i0 = Int(indexPointer[face * 3])
            let i1 = Int(indexPointer[face * 3 + 1])
            let i2 = Int(indexPointer[face * 3 + 2])
            guard i0 < vertices.count, i1 < vertices.count, i2 < vertices.count else { continue }
            let a = vertices[i0], b = vertices[i1], c = vertices[i2]
            let centroid = (a + b + c) / 3
            let key = SIMD3<Int32>(Int32(floor((centroid.x - minBound.x) / cell)),
                                   Int32(floor((centroid.y - minBound.y) / cell)),
                                   Int32(floor((centroid.z - minBound.z) / cell)))
            var shard = cells[key] ?? Shard()
            let base = UInt32(shard.positions.count)
            shard.positions.append(contentsOf: [a, b, c])
            shard.indices.append(contentsOf: [base, base + 1, base + 2])
            cells[key] = shard
        }

        return cells.values.compactMap { shard in
            guard shard.indices.count >= 3 else { return nil }
            var s = shard
            s.centroid = s.positions.reduce(.zero, +) / Float(s.positions.count)
            // Recenter so the entity origin is the shard centroid.
            s.positions = s.positions.map { $0 - s.centroid }
            return s
        }
    }

    private static func makeShardEntity(shard: Shard,
                                        material: RealityKit.Material,
                                        configuration: RoomFXConfiguration) -> ModelEntity? {
        var descriptor = MeshDescriptor(name: "meshShard")
        descriptor.positions = MeshBuffers.Positions(shard.positions)
        descriptor.primitives = .triangles(shard.indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "RoomFX.MeshShard"
        entity.position = shard.centroid

        let bounds = entity.visualBounds(relativeTo: entity)
        let shape = ShapeResource.generateBox(size: max(bounds.extents, SIMD3<Float>(repeating: 0.02)))
        entity.collision = CollisionComponent(shapes: [shape])

        if configuration.physicsMode == .physics {
            entity.components.set(PhysicsBodyComponent(massProperties: .init(mass: 0.8),
                                                       material: .generate(friction: 0.8, restitution: 0.05),
                                                       mode: .dynamic))
        }
        return entity
    }

    private static func applyMotion(to entity: ModelEntity,
                                    shard: Shard,
                                    localImpact: SIMD3<Float>?,
                                    root: Entity,
                                    configuration: RoomFXConfiguration,
                                    rng: inout RoomFXRandom) {
        var away = SIMD3<Float>(rng.float(in: -1...1), 0.6, rng.float(in: -1...1))
        if let localImpact {
            let delta = shard.centroid - localImpact
            if simd_length(delta) > 1e-4 { away = simd_normalize(delta) + SIMD3<Float>(0, 0.4, 0) }
        }
        let speed = configuration.shardImpulse * (0.5 + configuration.crackIntensity)
            * rng.float(in: 0.6...1.2)
        let velocity = simd_normalize(away) * speed

        switch configuration.physicsMode {
        case .physics:
            entity.components.set(PhysicsMotionComponent(
                linearVelocity: root.convert(direction: velocity, to: nil),
                angularVelocity: SIMD3<Float>(rng.float(in: -5...5),
                                              rng.float(in: -5...5),
                                              rng.float(in: -5...5))))
        case .animated:
            var transform = entity.transform
            transform.translation += velocity * Float(configuration.shardAnimationDuration)
            transform.translation.y -= 0.5
            transform.scale = SIMD3<Float>(repeating: 0.01)
            entity.move(to: transform, relativeTo: root,
                        duration: configuration.shardAnimationDuration,
                        timingFunction: .easeIn)
        }
    }
}
