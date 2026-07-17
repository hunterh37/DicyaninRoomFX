# DicyaninRoomFX

Scene-reconstruction-driven environmental effects for visionOS: walls crack open onto portals, floors flood, real scanned geometry shatters along its actual triangles. Built on `DicyaninSceneReconstruction`.

## Effects

- **Wall crack open**: procedurally generated branching cracks (deterministic, seeded) grow across the real wall surface with a glowing light bleed, strain, then burst into physical shards revealing a RealityKit portal behind the geometry.
- **Floor flood**: rising translucent water sized to the scanned floor extent, with surface bob and a drain-out.
- **Mesh shatter**: reads the `MeshAnchor`'s real triangles, clusters them spatially, and spawns each cluster as a flying shard, so breakage lines follow the actual room geometry.

## Usage

```swift
import DicyaninRoomFX
import DicyaninSceneReconstruction

let reconstruction = SceneReconstructionManager()
let roomFX = RoomFXManager(sceneReconstruction: reconstruction)

// Knobs
roomFX.configuration.physicsMode = .physics      // or .animated
roomFX.configuration.crackIntensity = 0.9        // 0...1
roomFX.configuration.crackJaggedness = 0.6
roomFX.configuration.portalEnabled = true

// Crack the wall the user is looking at
if let effect = roomFX.crackWall(from: headPosition, direction: gazeDirection) {
    content.add(effect.rootEntity)
    effect.start()
}

// Flood the floor under the user
if let flood = roomFX.flood(under: headPosition) {
    content.add(flood.rootEntity)
    flood.start()
}

// Shatter the scanned mesh chunk near an explosion
if let debris = roomFX.shatterMesh(near: explosionPoint) {
    content.add(debris)
}
```

Custom portal worlds: pass any entity (skybox, scene) as `worldContent` to `crackWall`.

## Parameters

`RoomFXConfiguration` exposes: `physicsMode`, `crackIntensity`, `seed`, `crackBaseWidth`, `crackJaggedness`, `crackBranchProbability`, `crackMaxDepth`, `primaryCrackCount`, `crackStepLength`, `crackGrowDuration`, `crackGlowColor`, `crackGlowStrength`, `portalEnabled`, `portalRadius`, `shardThickness`, `shardImpulse`, `shardAnimationDuration`, `debrisLifetime`, `floodRiseSpeed`, `floodMaxHeight`, `floodColor`, `floodOpacity`, `shatterPieceCount`.

Same seed and parameters always produce the same cracks; with no explicit seed, the seed derives from the impact's world position so a given wall point always cracks the same way.

## Requirements

- visionOS 2.0+
- Scene reconstruction hardware (effects place via `SceneMeshRaycaster` against the scanned mesh)
