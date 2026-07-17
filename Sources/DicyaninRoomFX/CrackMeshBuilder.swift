//
//  CrackMeshBuilder.swift
//  DicyaninRoomFX
//
//  Turns a CrackPattern into RealityKit geometry: a jagged dark ribbon per
//  branch (the crack void) plus an optional narrower emissive ribbon (portal
//  light bleeding through). Meshes live in the wall plane (XY, +Z out of wall).
//

import Foundation
import RealityKit
import simd

/// Builds crack ribbon meshes from procedural crack patterns.
@MainActor
public enum CrackMeshBuilder {

    /// Geometry buffers for a partially or fully grown pattern.
    struct RibbonGeometry {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        mutating func append(_ other: RibbonGeometry) {
            let base = UInt32(positions.count)
            positions.append(contentsOf: other.positions)
            normals.append(contentsOf: other.normals)
            indices.append(contentsOf: other.indices.map { $0 + base })
        }

        var isEmpty: Bool { indices.isEmpty }
    }

    /// Builds the crack entity for a pattern at a given growth amount.
    ///
    /// - Parameters:
    ///   - pattern: The procedural pattern to mesh.
    ///   - growth: `0...1` — how far along their length branches are revealed.
    ///   - widthScale: Multiplier on crack width (used while a wall "strains").
    ///   - configuration: Colors and glow tunables.
    /// - Returns: An entity containing the dark crack ribbon and, when glow is
    ///   enabled, an emissive under-ribbon. Local space: wall plane, +Z outward.
    public static func makeEntity(pattern: CrackPattern,
                                  growth: Float,
                                  widthScale: Float = 1,
                                  configuration: RoomFXConfiguration) -> Entity {
        let root = Entity()
        root.name = "RoomFX.CrackMesh"

        guard let darkMesh = mesh(for: pattern, growth: growth,
                                  widthScale: widthScale, zOffset: 0.004) else { return root }
        var darkMaterial = UnlitMaterial(color: .black)
        darkMaterial.faceCulling = .none
        root.addChild(ModelEntity(mesh: darkMesh, materials: [darkMaterial]))

        if configuration.crackGlowStrength > 0,
           let glowMesh = mesh(for: pattern, growth: growth,
                               widthScale: widthScale * 0.45, zOffset: 0.006) {
            let g = configuration.crackGlowColor * configuration.crackGlowStrength
            var glowMaterial = UnlitMaterial(color: RoomFXColor(red: CGFloat(min(g.x, 1)),
                                                                green: CGFloat(min(g.y, 1)),
                                                                blue: CGFloat(min(g.z, 1)),
                                                                alpha: 1))
            glowMaterial.faceCulling = .none
            glowMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.9))
            root.addChild(ModelEntity(mesh: glowMesh, materials: [glowMaterial]))
        }
        return root
    }

    /// Builds a single `MeshResource` ribbon set for the pattern, or `nil` when
    /// growth is too small to produce any triangles.
    static func mesh(for pattern: CrackPattern,
                     growth: Float,
                     widthScale: Float,
                     zOffset: Float) -> MeshResource? {
        var geometry = RibbonGeometry()
        for branch in pattern.branches {
            // Child branches start growing after their parent has some length.
            let localGrowth = min(max((growth - Float(branch.depth) * 0.15) / 0.85, 0), 1)
            guard localGrowth > 0.02 else { continue }
            geometry.append(ribbon(for: branch, growth: localGrowth,
                                   widthScale: widthScale, zOffset: zOffset))
        }
        guard !geometry.isEmpty else { return nil }

        var descriptor = MeshDescriptor(name: "crackRibbon")
        descriptor.positions = MeshBuffers.Positions(geometry.positions)
        descriptor.normals = MeshBuffers.Normals(geometry.normals)
        descriptor.primitives = .triangles(geometry.indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    /// Meshes one branch as a jagged triangle ribbon up to `growth` of its length.
    private static func ribbon(for branch: CrackBranch,
                               growth: Float,
                               widthScale: Float,
                               zOffset: Float) -> RibbonGeometry {
        var geometry = RibbonGeometry()
        let visible = branch.nodes.filter { $0.progress <= growth }
        guard visible.count >= 2 else { return geometry }

        // Two offset edges per node, jittered deterministically per index so
        // rims look chipped rather than smooth.
        for (index, node) in visible.enumerated() {
            let ahead = index + 1 < visible.count ? visible[index + 1].position : node.position
            let behind = index > 0 ? visible[index - 1].position : node.position
            var tangent = ahead - behind
            if simd_length(tangent) < 1e-5 { tangent = SIMD2<Float>(1, 0) }
            tangent = simd_normalize(tangent)
            let normal2D = SIMD2<Float>(-tangent.y, tangent.x)

            let jitter = 1 + 0.35 * sin(Float(index) * 12.9898 + node.position.x * 78.233)
            let halfWidth = node.halfWidth * widthScale * jitter
            let left = node.position + normal2D * halfWidth
            let right = node.position - normal2D * halfWidth

            geometry.positions.append(SIMD3<Float>(left.x, left.y, zOffset))
            geometry.positions.append(SIMD3<Float>(right.x, right.y, zOffset))
            geometry.normals.append(SIMD3<Float>(0, 0, 1))
            geometry.normals.append(SIMD3<Float>(0, 0, 1))

            if index > 0 {
                let i = UInt32(index * 2)
                // Quad between the previous pair and this pair.
                geometry.indices.append(contentsOf: [i - 2, i - 1, i,
                                                     i, i - 1, i + 1])
            }
        }
        return geometry
    }
}
