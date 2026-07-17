//
//  FloorFloodEffect.swift
//  DicyaninRoomFX
//
//  Rising water over the real scanned floor: a translucent plane sized to the
//  scene mesh's floor extent that climbs to a configured height with a gentle
//  surface bob. Uses the reconstructed geometry for placement and sizing.
//

import Foundation
import RealityKit
import simd

/// One flood instance. Create via ``RoomFXManager/flood(floorY:center:extent:)``
/// or directly, then call ``start()``.
@MainActor
public final class FloorFloodEffect {

    /// Root entity containing the water surface. Add to your scene.
    public let rootEntity: Entity
    /// Current water height above the floor, meters.
    public private(set) var currentHeight: Float = 0
    /// `true` while the water is rising or bobbing.
    public private(set) var isRunning = false

    private let configuration: RoomFXConfiguration
    private let floorY: Float
    private let surface: ModelEntity
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - floorY: World-space Y of the detected floor.
    ///   - center: World-space XZ center of the flooded region.
    ///   - extent: Size of the water plane in meters (x = width, y = depth).
    ///   - configuration: Flood tunables (speed, max height, color, opacity).
    public init(floorY: Float,
                center: SIMD2<Float>,
                extent: SIMD2<Float>,
                configuration: RoomFXConfiguration) {
        self.configuration = configuration
        self.floorY = floorY

        var material = PhysicallyBasedMaterial()
        let c = configuration.floodColor
        material.baseColor = .init(tint: RoomFXColor(red: CGFloat(c.x),
                                                     green: CGFloat(c.y),
                                                     blue: CGFloat(c.z),
                                                     alpha: 1))
        material.roughness = .init(floatLiteral: 0.05)
        material.metallic = .init(floatLiteral: 0.2)
        material.blending = .transparent(opacity: .init(floatLiteral: configuration.floodOpacity))
        material.faceCulling = .none

        let mesh = MeshResource.generatePlane(width: max(extent.x, 0.1),
                                              depth: max(extent.y, 0.1))
        surface = ModelEntity(mesh: mesh, materials: [material])
        surface.name = "RoomFX.FloodSurface"

        let root = Entity()
        root.name = "RoomFX.Flood"
        root.position = SIMD3<Float>(center.x, floorY + 0.002, center.y)
        root.addChild(surface)
        rootEntity = root
    }

    /// Starts the water rising to ``RoomFXConfiguration/floodMaxHeight``.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        task = Task { [weak self] in
            guard let self else { return }
            let speed = self.configuration.floodRiseSpeed
                * (0.4 + 0.6 * self.configuration.crackIntensity)
            let dt: Float = 1.0 / 30.0
            var time: Float = 0
            while !Task.isCancelled {
                time += dt
                if self.currentHeight < self.configuration.floodMaxHeight {
                    self.currentHeight = min(self.currentHeight + speed * dt,
                                             self.configuration.floodMaxHeight)
                }
                // Gentle surface bob so the water reads as liquid.
                let bob = sin(time * 1.7) * 0.006 + sin(time * 3.1) * 0.003
                self.surface.position.y = self.currentHeight + bob
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    /// Drains the water back down, then removes the entity.
    public func drain() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            let dt: Float = 1.0 / 30.0
            while !Task.isCancelled, self.currentHeight > 0 {
                self.currentHeight = max(0, self.currentHeight - self.configuration.floodRiseSpeed * 3 * dt)
                self.surface.position.y = self.currentHeight
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
            self.stop()
        }
    }

    /// Stops immediately and removes the water from the scene.
    public func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        rootEntity.removeFromParent()
    }
}
