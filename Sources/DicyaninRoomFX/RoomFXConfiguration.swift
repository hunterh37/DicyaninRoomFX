//
//  RoomFXConfiguration.swift
//  DicyaninRoomFX
//
//  Central tunables for every RoomFX effect. All effects take a configuration
//  at spawn time; mutating a manager's configuration affects new effects only.
//

import Foundation
import simd
#if canImport(UIKit)
import UIKit
public typealias RoomFXColor = UIColor
#endif

/// How opened wall shards and shattered mesh pieces move.
public enum RoomFXPhysicsMode: Sendable, Equatable {
    /// Shards get dynamic physics bodies (gravity, impulses, collisions).
    case physics
    /// Shards are animated kinematically (cheap, deterministic, no physics sim).
    case animated
}

/// Tunables for every RoomFX effect.
public struct RoomFXConfiguration: Sendable {

    // MARK: Global

    /// Physics toggle for shards, debris, and shattered chunks.
    public var physicsMode: RoomFXPhysicsMode

    /// Master intensity, `0...1`. Scales crack density, branch count, width,
    /// shard impulse, flood speed. Clamped on set.
    public var crackIntensity: Float {
        didSet { crackIntensity = min(max(crackIntensity, 0), 1) }
    }

    /// Seed for all procedural generation. Same seed + parameters = same cracks.
    /// `nil` derives a seed from the effect's world position (stable per wall).
    public var seed: UInt64?

    // MARK: Cracks

    /// Base crack half-width in meters at full intensity.
    public var crackBaseWidth: Float
    /// Angular jitter per growth step, radians. Higher = more jagged cracks.
    public var crackJaggedness: Float
    /// Probability per node that a crack forks into a child branch.
    public var crackBranchProbability: Float
    /// Maximum branch recursion depth.
    public var crackMaxDepth: Int
    /// Number of primary cracks radiating from the impact point.
    public var primaryCrackCount: Int
    /// Growth-step length in meters.
    public var crackStepLength: Float
    /// Seconds for cracks to grow to full extent.
    public var crackGrowDuration: TimeInterval
    /// Emissive glow color seeping out of the cracks (portal light bleed).
    public var crackGlowColor: SIMD3<Float>
    /// Glow strength multiplier. `0` disables the glow pass entirely.
    public var crackGlowStrength: Float

    // MARK: Wall opening

    /// Whether opening a wall reveals a portal behind the shards.
    public var portalEnabled: Bool
    /// Portal radius in meters.
    public var portalRadius: Float
    /// Shard slab thickness in meters (fake wall depth).
    public var shardThickness: Float
    /// Outward impulse applied to shards, scaled by ``crackIntensity``.
    public var shardImpulse: Float
    /// Seconds animated shards take to fly out and fade (animated mode).
    public var shardAnimationDuration: TimeInterval
    /// Seconds before spawned shards/debris are removed from the scene.
    public var debrisLifetime: TimeInterval

    // MARK: Flood

    /// Meters per second the flood water rises, scaled by ``crackIntensity``.
    public var floodRiseSpeed: Float
    /// Maximum flood height above the floor, in meters.
    public var floodMaxHeight: Float
    /// Water tint.
    public var floodColor: SIMD3<Float>
    /// Water opacity, `0...1`.
    public var floodOpacity: Float

    // MARK: Shatter

    /// Approximate shard count when shattering a scene-mesh chunk.
    public var shatterPieceCount: Int

    public init(physicsMode: RoomFXPhysicsMode = .physics,
                crackIntensity: Float = 0.7,
                seed: UInt64? = nil,
                crackBaseWidth: Float = 0.012,
                crackJaggedness: Float = 0.55,
                crackBranchProbability: Float = 0.28,
                crackMaxDepth: Int = 3,
                primaryCrackCount: Int = 5,
                crackStepLength: Float = 0.09,
                crackGrowDuration: TimeInterval = 1.6,
                crackGlowColor: SIMD3<Float> = SIMD3<Float>(1.0, 0.55, 0.15),
                crackGlowStrength: Float = 1.0,
                portalEnabled: Bool = true,
                portalRadius: Float = 0.55,
                shardThickness: Float = 0.05,
                shardImpulse: Float = 2.2,
                shardAnimationDuration: TimeInterval = 1.2,
                debrisLifetime: TimeInterval = 6.0,
                floodRiseSpeed: Float = 0.06,
                floodMaxHeight: Float = 0.5,
                floodColor: SIMD3<Float> = SIMD3<Float>(0.1, 0.32, 0.45),
                floodOpacity: Float = 0.65,
                shatterPieceCount: Int = 24) {
        self.physicsMode = physicsMode
        self.crackIntensity = min(max(crackIntensity, 0), 1)
        self.seed = seed
        self.crackBaseWidth = crackBaseWidth
        self.crackJaggedness = crackJaggedness
        self.crackBranchProbability = crackBranchProbability
        self.crackMaxDepth = crackMaxDepth
        self.primaryCrackCount = primaryCrackCount
        self.crackStepLength = crackStepLength
        self.crackGrowDuration = crackGrowDuration
        self.crackGlowColor = crackGlowColor
        self.crackGlowStrength = crackGlowStrength
        self.portalEnabled = portalEnabled
        self.portalRadius = portalRadius
        self.shardThickness = shardThickness
        self.shardImpulse = shardImpulse
        self.shardAnimationDuration = shardAnimationDuration
        self.debrisLifetime = debrisLifetime
        self.floodRiseSpeed = floodRiseSpeed
        self.floodMaxHeight = floodMaxHeight
        self.floodColor = floodColor
        self.floodOpacity = floodOpacity
        self.shatterPieceCount = shatterPieceCount
    }
}
