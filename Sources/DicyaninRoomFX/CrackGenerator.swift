//
//  CrackGenerator.swift
//  DicyaninRoomFX
//
//  Deterministic procedural crack patterns: recursive branching random walks in
//  the 2D plane of a wall. Pure value-type logic, no RealityKit, fully testable.
//

import Foundation
import simd

/// Deterministic seedable RNG (SplitMix64). Same seed = same crack pattern.
public struct RoomFXRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { self.state = seed &+ 0x9E3779B97F4A7C15 }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform float in `range`.
    public mutating func float(in range: ClosedRange<Float>) -> Float {
        Float.random(in: range, using: &self)
    }
}

/// One vertex along a crack branch, in wall-local 2D space (meters).
public struct CrackNode: Sendable, Equatable {
    /// Position in the wall plane. Origin = impact point. +Y = wall-local up.
    public var position: SIMD2<Float>
    /// Half-width of the crack at this node, meters.
    public var halfWidth: Float
    /// Normalized distance from the branch start, `0...1`.
    public var progress: Float
}

/// A single crack polyline. Depth 0 branches radiate from the impact point.
public struct CrackBranch: Sendable {
    public var nodes: [CrackNode]
    public var depth: Int
}

/// A full procedurally generated crack pattern for one wall impact.
public struct CrackPattern: Sendable {
    public var branches: [CrackBranch]
    public var seed: UInt64
    /// Radius of the pattern's extent from the impact point, meters.
    public var radius: Float

    /// Outward unit directions of the depth-0 branches, used to cut wall shards.
    public var primaryDirections: [SIMD2<Float>] {
        branches.filter { $0.depth == 0 }.compactMap { branch in
            guard let last = branch.nodes.last, simd_length(last.position) > 1e-4 else { return nil }
            return simd_normalize(last.position)
        }
    }
}

/// Generates crack patterns. Stateless; all knobs come from the configuration.
public enum CrackGenerator {

    /// Generates a deterministic crack pattern.
    ///
    /// - Parameters:
    ///   - configuration: RoomFX tunables (intensity, jaggedness, branching...).
    ///   - maxRadius: Cap on how far cracks may travel from the impact, meters.
    ///   - seed: RNG seed. Same seed and parameters produce identical output.
    public static func generate(configuration: RoomFXConfiguration,
                                maxRadius: Float,
                                seed: UInt64) -> CrackPattern {
        var rng = RoomFXRandom(seed: seed)
        let intensity = configuration.crackIntensity
        // Intensity scales both reach and primary count.
        let reach = max(0.15, maxRadius * (0.35 + 0.65 * intensity))
        let primaries = max(2, Int((Float(configuration.primaryCrackCount) * (0.5 + intensity)).rounded()))

        var branches: [CrackBranch] = []
        let baseAngle = rng.float(in: 0...(2 * .pi))
        for i in 0..<primaries {
            let slice = (2 * Float.pi) / Float(primaries)
            let angle = baseAngle + Float(i) * slice + rng.float(in: -slice * 0.3...slice * 0.3)
            let direction = SIMD2<Float>(cos(angle), sin(angle))
            grow(from: .zero,
                 direction: direction,
                 length: reach * rng.float(in: 0.7...1.0),
                 halfWidth: configuration.crackBaseWidth * (0.5 + intensity),
                 depth: 0,
                 configuration: configuration,
                 into: &branches,
                 rng: &rng)
        }
        return CrackPattern(branches: branches, seed: seed, radius: reach)
    }

    /// Grows one branch as a jittered random walk, recursively forking children.
    private static func grow(from origin: SIMD2<Float>,
                             direction: SIMD2<Float>,
                             length: Float,
                             halfWidth: Float,
                             depth: Int,
                             configuration: RoomFXConfiguration,
                             into branches: inout [CrackBranch],
                             rng: inout RoomFXRandom) {
        guard depth <= configuration.crackMaxDepth, length > configuration.crackStepLength else { return }

        let stepCount = max(2, Int(length / configuration.crackStepLength))
        var nodes: [CrackNode] = []
        var position = origin
        var heading = atan2(direction.y, direction.x)

        nodes.append(CrackNode(position: position, halfWidth: halfWidth, progress: 0))

        for step in 1...stepCount {
            let progress = Float(step) / Float(stepCount)
            heading += rng.float(in: -configuration.crackJaggedness...configuration.crackJaggedness)
            position += SIMD2<Float>(cos(heading), sin(heading)) * configuration.crackStepLength
            // Cracks taper toward the tip.
            let width = halfWidth * (1 - progress * 0.85)
            nodes.append(CrackNode(position: position, halfWidth: width, progress: progress))

            // Fork a thinner child branch.
            if depth < configuration.crackMaxDepth,
               rng.float(in: 0...1) < configuration.crackBranchProbability {
                let side: Float = rng.float(in: 0...1) < 0.5 ? 1 : -1
                let childAngle = heading + side * rng.float(in: 0.5...1.2)
                grow(from: position,
                     direction: SIMD2<Float>(cos(childAngle), sin(childAngle)),
                     length: length * (1 - progress) * rng.float(in: 0.4...0.7),
                     halfWidth: width * 0.6,
                     depth: depth + 1,
                     configuration: configuration,
                     into: &branches,
                     rng: &rng)
            }
        }
        branches.append(CrackBranch(nodes: nodes, depth: depth))
    }

    /// Stable seed derived from a world position, so the same wall point always
    /// cracks the same way when no explicit seed is configured.
    public static func seed(for worldPosition: SIMD3<Float>) -> UInt64 {
        let q = SIMD3<Int32>((worldPosition * 100).rounded(.toNearestOrEven))
        var hash: UInt64 = 0xcbf29ce484222325
        for value in [q.x, q.y, q.z] {
            hash = (hash ^ UInt64(bitPattern: Int64(value))) &* 0x100000001b3
        }
        return hash
    }
}
