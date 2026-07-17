//
//  WallCrackEffect.swift
//  DicyaninRoomFX
//
//  The classic VR wall-crack-open effect. Anchored to a point + normal on the
//  real scanned wall: procedural cracks grow across the surface, strain, then
//  the wall bursts into physical shards revealing a portal behind the geometry.
//

import Foundation
import RealityKit
import simd

/// One wall-crack-open instance. Create via ``RoomFXManager/crackWall(at:normal:in:worldContent:)``
/// or directly, then call ``start()``.
@MainActor
public final class WallCrackEffect {

    public enum Phase: Sendable, Equatable {
        case idle, cracking, strained, open, finished
    }

    /// Root entity, positioned on the wall and oriented so local +Z is the wall
    /// normal (out of the wall). Add to your scene before calling ``start()``.
    public let rootEntity: Entity
    public private(set) var phase: Phase = .idle
    public let pattern: CrackPattern
    /// Called on phase changes (grow finished, wall opened, effect done).
    public var onPhaseChange: ((Phase) -> Void)?

    private let configuration: RoomFXConfiguration
    private let wallNormal: SIMD3<Float>
    private let worldContent: Entity?
    private var crackEntity: Entity?
    private var animationTask: Task<Void, Never>?

    /// - Parameters:
    ///   - worldPosition: Impact point on the wall (world space).
    ///   - wallNormal: Wall surface normal at the impact (world space).
    ///   - configuration: Effect tunables.
    ///   - maxRadius: Cap on crack spread, meters. Default `1.4`.
    ///   - worldContent: Optional content for the revealed portal world.
    public init(worldPosition: SIMD3<Float>,
                wallNormal: SIMD3<Float>,
                configuration: RoomFXConfiguration,
                maxRadius: Float = 1.4,
                worldContent: Entity? = nil) {
        self.configuration = configuration
        self.wallNormal = simd_normalize(wallNormal)
        self.worldContent = worldContent

        let seed = configuration.seed ?? CrackGenerator.seed(for: worldPosition)
        self.pattern = CrackGenerator.generate(configuration: configuration,
                                               maxRadius: maxRadius,
                                               seed: seed)

        let root = Entity()
        root.name = "RoomFX.WallCrack"
        root.position = worldPosition + self.wallNormal * 0.005
        root.orientation = Self.orientation(alignedTo: self.wallNormal)
        self.rootEntity = root
    }

    /// Runs the full sequence: grow cracks, strain, burst open, cleanup.
    public func start() {
        guard phase == .idle else { return }
        setPhase(.cracking)
        animationTask = Task { [weak self] in
            guard let self else { return }
            await self.growCracks()
            guard !Task.isCancelled else { return }
            await self.strain()
            guard !Task.isCancelled else { return }
            self.open()
            try? await Task.sleep(nanoseconds: UInt64(self.configuration.debrisLifetime * 1e9))
            self.finish()
        }
    }

    /// Cancels the sequence and removes all spawned entities.
    public func cancel() {
        animationTask?.cancel()
        animationTask = nil
        rootEntity.removeFromParent()
        setPhase(.finished)
    }

    // MARK: - Sequence

    private func growCracks() async {
        let frames = max(8, Int(configuration.crackGrowDuration * 30))
        for frame in 0...frames {
            guard !Task.isCancelled else { return }
            let t = Float(frame) / Float(frames)
            // Ease-out growth: fast initial split, slow creep at the tips.
            rebuildCracks(growth: 1 - pow(1 - t, 2.2), widthScale: 1)
            try? await Task.sleep(nanoseconds: UInt64(configuration.crackGrowDuration / Double(frames) * 1e9))
        }
    }

    private func strain() async {
        setPhase(.strained)
        let pulses = 3
        for pulse in 0..<pulses {
            guard !Task.isCancelled else { return }
            let scale = 1 + Float(pulse + 1) * 0.6 * configuration.crackIntensity
            rebuildCracks(growth: 1, widthScale: scale)
            try? await Task.sleep(nanoseconds: 140_000_000)
        }
    }

    private func rebuildCracks(growth: Float, widthScale: Float) {
        crackEntity?.removeFromParent()
        let entity = CrackMeshBuilder.makeEntity(pattern: pattern,
                                                 growth: growth,
                                                 widthScale: widthScale,
                                                 configuration: configuration)
        rootEntity.addChild(entity)
        crackEntity = entity
    }

    private func open() {
        crackEntity?.removeFromParent()
        crackEntity = nil

        if configuration.portalEnabled {
            let reveal = PortalRevealBuilder.makeReveal(configuration: configuration,
                                                        seed: pattern.seed,
                                                        worldContent: worldContent)
            reveal.portal.position = SIMD3<Float>(0, 0, -0.01)
            rootEntity.addChild(reveal.portal)
        }

        spawnShards()
        setPhase(.open)
    }

    private func spawnShards() {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: RoomFXColor(white: 0.82, alpha: 1))
        material.roughness = .init(floatLiteral: 0.9)

        let shards = WallShardBuilder.shards(for: pattern)
        var rng = RoomFXRandom(seed: pattern.seed ^ 0xF1E5)
        for shard in shards {
            guard let entity = WallShardBuilder.makeEntity(for: shard,
                                                           configuration: configuration,
                                                           material: material) else { continue }
            rootEntity.addChild(entity)

            let outward2D = shard.outwardDirection
            let impulseScale = configuration.shardImpulse * (0.5 + configuration.crackIntensity)
            // Local space: +Z is out of the wall; shards fly outward and forward.
            let velocity = simd_normalize(SIMD3<Float>(outward2D.x * 0.4,
                                                       outward2D.y * 0.4,
                                                       1)) * impulseScale * rng.float(in: 0.7...1.3)
            let worldVelocity = rootEntity.convert(direction: velocity, to: nil)

            switch configuration.physicsMode {
            case .physics:
                entity.components.set(PhysicsMotionComponent(
                    linearVelocity: worldVelocity,
                    angularVelocity: SIMD3<Float>(rng.float(in: -4...4),
                                                  rng.float(in: -4...4),
                                                  rng.float(in: -4...4))))
            case .animated:
                animate(shard: entity, velocity: velocity, rng: &rng)
            }
        }
    }

    /// Kinematic fallback: fly out, tumble, shrink to nothing.
    private func animate(shard: ModelEntity, velocity: SIMD3<Float>, rng: inout RoomFXRandom) {
        let duration = configuration.shardAnimationDuration
        let spin = simd_quatf(angle: rng.float(in: 1.5...3.5),
                              axis: simd_normalize(SIMD3<Float>(rng.float(in: -1...1),
                                                                rng.float(in: -1...1),
                                                                rng.float(in: -1...1))))
        var transform = shard.transform
        transform.translation += velocity * Float(duration) * 0.8
        transform.rotation = spin * transform.rotation
        transform.scale = SIMD3<Float>(repeating: 0.01)
        shard.move(to: transform, relativeTo: rootEntity, duration: duration,
                   timingFunction: .easeOut)
    }

    private func finish() {
        // Keep the portal; drop the debris.
        for child in rootEntity.children where child.name == "RoomFX.WallShard" {
            child.removeFromParent()
        }
        setPhase(.finished)
    }

    private func setPhase(_ newPhase: Phase) {
        phase = newPhase
        onPhaseChange?(newPhase)
    }

    /// Rotation taking local +Z onto the wall normal, with a stable up vector.
    static func orientation(alignedTo normal: SIMD3<Float>) -> simd_quatf {
        let z = simd_normalize(normal)
        let reference: SIMD3<Float> = abs(z.y) > 0.95 ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(0, 1, 0)
        let x = simd_normalize(simd_cross(reference, z))
        let y = simd_cross(z, x)
        return simd_quatf(simd_float3x3(columns: (x, y, z)))
    }
}
