//
//  RoomFXManager.swift
//  DicyaninRoomFX
//
//  Entry point tying RoomFX to DicyaninSceneReconstruction: raycasts the real
//  scanned mesh to place effects, tracks live effect instances, and exposes the
//  physics-mode / crack-intensity knobs in one place.
//

import ARKit
import Foundation
import RealityKit
import simd
import DicyaninSceneReconstruction

/// Scene-reconstruction-driven environmental effects: crack walls open onto
/// portals, flood floors, shatter real geometry.
///
/// ```swift
/// let roomFX = RoomFXManager(sceneReconstruction: reconstructionManager)
/// roomFX.configuration.physicsMode = .physics
/// roomFX.configuration.crackIntensity = 0.9
/// if let effect = roomFX.crackWall(from: headPosition, direction: gazeDirection) {
///     content.add(effect.rootEntity)
///     effect.start()
/// }
/// ```
@MainActor
public final class RoomFXManager: ObservableObject {

    /// Tunables applied to every effect spawned after the change.
    @Published public var configuration: RoomFXConfiguration

    /// Live wall-crack effects (finished effects are pruned on next spawn).
    public private(set) var wallCracks: [WallCrackEffect] = []
    /// Live flood effects.
    public private(set) var floods: [FloorFloodEffect] = []

    private let sceneReconstruction: SceneReconstructionManager

    public init(sceneReconstruction: SceneReconstructionManager,
                configuration: RoomFXConfiguration = RoomFXConfiguration()) {
        self.sceneReconstruction = sceneReconstruction
        self.configuration = configuration
    }

    // MARK: - Wall cracks

    /// Raycasts the real scene mesh and cracks open the wall it hits.
    ///
    /// - Parameters:
    ///   - origin: World-space ray origin (e.g. head or muzzle position).
    ///   - direction: Ray direction toward the wall.
    ///   - maxDistance: Maximum ray length, meters.
    ///   - worldContent: Optional content for the revealed portal world.
    /// - Returns: The effect (not yet started, root not yet parented), or `nil`
    ///   when the ray misses the scanned mesh. Add ``WallCrackEffect/rootEntity``
    ///   to your content, then call ``WallCrackEffect/start()``.
    public func crackWall(from origin: SIMD3<Float>,
                          direction: SIMD3<Float>,
                          maxDistance: Float = 10,
                          worldContent: Entity? = nil) -> WallCrackEffect? {
        guard let scene = sceneReconstruction.rootEntity.scene,
              let hit = SceneMeshRaycaster.raycast(from: origin,
                                                   direction: direction,
                                                   in: scene,
                                                   meshEntities: sceneReconstruction.meshEntities,
                                                   maxDistance: maxDistance) else { return nil }
        return crackWall(at: hit.position, normal: hit.normal, worldContent: worldContent)
    }

    /// Cracks open a wall at a known point and surface normal.
    public func crackWall(at position: SIMD3<Float>,
                          normal: SIMD3<Float>,
                          maxRadius: Float = 1.4,
                          worldContent: Entity? = nil) -> WallCrackEffect {
        wallCracks.removeAll { $0.phase == .finished }
        let effect = WallCrackEffect(worldPosition: position,
                                     wallNormal: normal,
                                     configuration: configuration,
                                     maxRadius: maxRadius,
                                     worldContent: worldContent)
        wallCracks.append(effect)
        return effect
    }

    // MARK: - Floods

    /// Floods the floor under `center`, sized from the scanned mesh bounds.
    ///
    /// - Parameters:
    ///   - center: World-space point above the floor to flood around.
    ///   - fallbackExtent: Plane size used when the floor extent is unknown.
    /// - Returns: The flood effect (root not yet parented, not yet started), or
    ///   `nil` when no floor is found below `center`.
    public func flood(under center: SIMD3<Float>,
                      fallbackExtent: SIMD2<Float> = SIMD2<Float>(6, 6)) -> FloorFloodEffect? {
        guard let scene = sceneReconstruction.rootEntity.scene,
              let hit = SceneMeshRaycaster.raycast(from: center,
                                                   direction: SIMD3<Float>(0, -1, 0),
                                                   in: scene,
                                                   meshEntities: sceneReconstruction.meshEntities,
                                                   maxDistance: 5) else { return nil }
        var extent = fallbackExtent
        if !sceneReconstruction.anchors.isEmpty {
            var bounds = BoundingBox()
            for anchor in sceneReconstruction.anchors {
                let local = anchor.boundingBox
                let transform = Transform(matrix: anchor.originFromAnchorTransform)
                bounds = bounds.union(local.min * transform.scale + transform.translation)
                bounds = bounds.union(local.max * transform.scale + transform.translation)
            }
            extent = SIMD2<Float>(max(bounds.extents.x, 1), max(bounds.extents.z, 1))
        }
        let effect = FloorFloodEffect(floorY: hit.position.y,
                                      center: SIMD2<Float>(center.x, center.z),
                                      extent: extent,
                                      configuration: configuration)
        floods.removeAll { !$0.isRunning }
        floods.append(effect)
        return effect
    }

    // MARK: - Shatter

    /// Shatters the scene-mesh anchor nearest to `worldPosition` along its real
    /// triangles. Hides the original chunk while debris flies.
    ///
    /// - Returns: The shatter root entity (already positioned; add it to your
    ///   content), or `nil` when no anchor is close enough.
    public func shatterMesh(near worldPosition: SIMD3<Float>,
                            impactPoint: SIMD3<Float>? = nil,
                            maxAnchorDistance: Float = 3) -> Entity? {
        var best: (anchor: MeshAnchor, entity: ModelEntity, distance: Float)?
        for (anchor, entity) in zip(sceneReconstruction.anchors, sceneReconstruction.meshEntities) {
            let anchorPosition = Transform(matrix: anchor.originFromAnchorTransform).translation
            let distance = simd_distance(anchorPosition, worldPosition)
            if distance <= maxAnchorDistance, distance < (best?.distance ?? .infinity) {
                best = (anchor, entity, distance)
            }
        }
        guard let best,
              let root = MeshShatterEffect.shatter(anchor: best.anchor,
                                                   impactPoint: impactPoint ?? worldPosition,
                                                   configuration: configuration) else { return nil }
        // Hide the intact chunk while the shards replace it.
        best.entity.isEnabled = false
        let lifetime = configuration.debrisLifetime
        let chunk = best.entity
        Task {
            try? await Task.sleep(nanoseconds: UInt64(lifetime * 1e9))
            chunk.isEnabled = true
        }
        return root
    }

    /// Cancels and removes every live effect.
    public func removeAll() {
        for effect in wallCracks { effect.cancel() }
        for flood in floods { flood.stop() }
        wallCracks.removeAll()
        floods.removeAll()
    }
}
