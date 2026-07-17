//
//  PortalRevealBuilder.swift
//  DicyaninRoomFX
//
//  Builds the "world behind the wall": a RealityKit portal plane whose target
//  is a `WorldComponent` entity. Apps can supply their own world content
//  (skybox, scene, lighting); a default glowing void is provided otherwise.
//

import Foundation
import RealityKit
import simd

/// Builds portal + world entity pairs for wall openings.
@MainActor
public enum PortalRevealBuilder {

    /// The result of building a portal reveal.
    public struct Reveal {
        /// The portal surface. Local space: faces +Z. Add at the wall opening.
        public let portal: Entity
        /// The world rendered through the portal. Already parented to `portal`.
        public let world: Entity
    }

    /// Builds a circular portal facing +Z with a jagged-rimmed disc mesh.
    ///
    /// - Parameters:
    ///   - configuration: Portal radius, glow color, seed.
    ///   - seed: Deterministic rim jitter seed.
    ///   - worldContent: Optional app-provided content to place inside the
    ///     portal world (e.g. a skybox or scene). Positioned behind the wall.
    public static func makeReveal(configuration: RoomFXConfiguration,
                                  seed: UInt64,
                                  worldContent: Entity? = nil) -> Reveal {
        let world = Entity()
        world.name = "RoomFX.PortalWorld"
        world.components.set(WorldComponent())

        if let worldContent {
            world.addChild(worldContent)
        } else {
            world.addChild(defaultWorldContent(configuration: configuration))
        }

        let portal = Entity()
        portal.name = "RoomFX.Portal"
        if let mesh = jaggedDiscMesh(radius: configuration.portalRadius, seed: seed) {
            let surface = ModelEntity(mesh: mesh, materials: [PortalMaterial()])
            surface.components.set(PortalComponent(target: world))
            portal.addChild(surface)
        }
        portal.addChild(world)
        return Reveal(portal: portal, world: world)
    }

    /// Fallback world: a glowing void sphere tinted with the crack glow color.
    static func defaultWorldContent(configuration: RoomFXConfiguration) -> Entity {
        let g = configuration.crackGlowColor
        var material = UnlitMaterial(color: RoomFXColor(red: CGFloat(min(g.x, 1)),
                                                        green: CGFloat(min(g.y, 1)),
                                                        blue: CGFloat(min(g.z, 1)),
                                                        alpha: 1))
        material.faceCulling = .front
        let sphere = ModelEntity(mesh: .generateSphere(radius: 6), materials: [material])
        sphere.name = "RoomFX.PortalVoid"
        sphere.position = SIMD3<Float>(0, 0, -3)
        return sphere
    }

    /// Fan-triangulated disc with a deterministically jagged rim, facing +Z.
    static func jaggedDiscMesh(radius: Float, seed: UInt64) -> MeshResource? {
        var rng = RoomFXRandom(seed: seed ^ 0xA17)
        let segments = 40
        var positions: [SIMD3<Float>] = [SIMD3<Float>(0, 0, 0)]
        var normals: [SIMD3<Float>] = [SIMD3<Float>(0, 0, 1)]
        var indices: [UInt32] = []

        for i in 0...segments {
            let angle = Float(i) / Float(segments) * 2 * .pi
            let r = i == segments ? simd_length(SIMD2<Float>(positions[1].x, positions[1].y))
                                  : radius * rng.float(in: 0.82...1.0)
            positions.append(SIMD3<Float>(cos(angle) * r, sin(angle) * r, 0))
            normals.append(SIMD3<Float>(0, 0, 1))
            if i > 0 {
                indices.append(contentsOf: [0, UInt32(i), UInt32(i + 1)])
            }
        }

        var descriptor = MeshDescriptor(name: "portalDisc")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
