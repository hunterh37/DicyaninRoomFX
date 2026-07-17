//
//  DicyaninRoomFXTests.swift
//  DicyaninRoomFX
//

import XCTest
import simd
@testable import DicyaninRoomFX

final class CrackGeneratorTests: XCTestCase {

    func testDeterministicForSameSeed() {
        let config = RoomFXConfiguration()
        let a = CrackGenerator.generate(configuration: config, maxRadius: 1.5, seed: 42)
        let b = CrackGenerator.generate(configuration: config, maxRadius: 1.5, seed: 42)
        XCTAssertEqual(a.branches.count, b.branches.count)
        XCTAssertEqual(a.radius, b.radius)
        for (ba, bb) in zip(a.branches, b.branches) {
            XCTAssertEqual(ba.nodes, bb.nodes)
        }
    }

    func testDifferentSeedsDiffer() {
        let config = RoomFXConfiguration()
        let a = CrackGenerator.generate(configuration: config, maxRadius: 1.5, seed: 1)
        let b = CrackGenerator.generate(configuration: config, maxRadius: 1.5, seed: 2)
        let aFirst = a.branches.first?.nodes.last?.position
        let bFirst = b.branches.first?.nodes.last?.position
        XCTAssertNotEqual(aFirst, bFirst)
    }

    func testIntensityScalesReach() {
        var low = RoomFXConfiguration(); low.crackIntensity = 0.1
        var high = RoomFXConfiguration(); high.crackIntensity = 1.0
        let a = CrackGenerator.generate(configuration: low, maxRadius: 2, seed: 7)
        let b = CrackGenerator.generate(configuration: high, maxRadius: 2, seed: 7)
        XCTAssertLessThan(a.radius, b.radius)
        XCTAssertLessThanOrEqual(a.branches.filter { $0.depth == 0 }.count,
                                 b.branches.filter { $0.depth == 0 }.count)
    }

    func testCracksStayNearMaxRadius() {
        let config = RoomFXConfiguration()
        let pattern = CrackGenerator.generate(configuration: config, maxRadius: 1.0, seed: 99)
        // Random-walk jitter can wander slightly past the nominal reach.
        for branch in pattern.branches {
            for node in branch.nodes {
                XCTAssertLessThan(simd_length(node.position), 2.0)
            }
        }
    }

    func testWidthsTaper() {
        let config = RoomFXConfiguration()
        let pattern = CrackGenerator.generate(configuration: config, maxRadius: 1.5, seed: 5)
        for branch in pattern.branches {
            guard let first = branch.nodes.first, let last = branch.nodes.last else { continue }
            XCTAssertLessThan(last.halfWidth, first.halfWidth)
        }
    }

    func testPositionSeedIsStable() {
        let p = SIMD3<Float>(1.234, 0.5, -2.1)
        XCTAssertEqual(CrackGenerator.seed(for: p), CrackGenerator.seed(for: p))
        XCTAssertNotEqual(CrackGenerator.seed(for: p),
                          CrackGenerator.seed(for: SIMD3<Float>(0, 0, 0)))
    }
}

final class RoomFXConfigurationTests: XCTestCase {

    func testIntensityClamped() {
        var config = RoomFXConfiguration(crackIntensity: 5)
        XCTAssertEqual(config.crackIntensity, 1)
        config.crackIntensity = -3
        XCTAssertEqual(config.crackIntensity, 0)
    }

    func testPhysicsModeToggle() {
        var config = RoomFXConfiguration(physicsMode: .physics)
        XCTAssertEqual(config.physicsMode, .physics)
        config.physicsMode = .animated
        XCTAssertEqual(config.physicsMode, .animated)
    }
}

@MainActor
final class WallShardBuilderTests: XCTestCase {

    func testShardsCoverPattern() {
        let config = RoomFXConfiguration()
        let pattern = CrackGenerator.generate(configuration: config, maxRadius: 1.2, seed: 11)
        let shards = WallShardBuilder.shards(for: pattern)
        XCTAssertGreaterThanOrEqual(shards.count, 2)
        for shard in shards {
            XCTAssertGreaterThanOrEqual(shard.outline.count, 3)
            XCTAssertEqual(simd_length(shard.outwardDirection), 1, accuracy: 1e-4)
        }
    }

    func testShardsDeterministic() {
        let config = RoomFXConfiguration()
        let pattern = CrackGenerator.generate(configuration: config, maxRadius: 1.2, seed: 11)
        let a = WallShardBuilder.shards(for: pattern)
        let b = WallShardBuilder.shards(for: pattern)
        XCTAssertEqual(a.count, b.count)
        for (sa, sb) in zip(a, b) { XCTAssertEqual(sa.outline, sb.outline) }
    }
}
