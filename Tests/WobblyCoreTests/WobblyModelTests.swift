// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import simd
import XCTest
@testable import WobblyCore

final class WobblyModelTests: XCTestCase {
    private let frame: Float = 1.0 / 120.0
    private let presets: [WobblySettings] = [.subtle, .realistic, .exaggerated, .extreme]

    /// Drags from the title bar a distance `delta` over `duration` seconds and releases.
    /// Returns the peak deformation and how long it takes to settle after release.
    private func simulateDrag(_ settings: WobblySettings, delta: SIMD2<Float>, duration: Float)
        -> (peak: Float, settle: Float, model: WobblyModel) {
        let start = SIMD2<Float>(200, 150)
        let grabLocal = SIMD2<Float>(300, 12)
        let model = WobblyModel(size: SIMD2(900, 600), origin: start, settings: settings)
        model.grab(at: start + grabLocal)

        var peak: Float = 0
        let steps = Int(duration / frame)
        for n in 1...steps {
            let t = Float(n) / Float(steps)
            let origin = start + delta * (t * t * (3 - 2 * t))
            model.moveGrab(to: origin + grabLocal, origin: origin)
            model.step(frame)
            peak = max(peak, model.maxDisplacement)
        }
        model.release(origin: start + delta)

        var elapsed: Float = 0
        repeat {
            model.step(frame)
            elapsed += frame
            peak = max(peak, model.maxDisplacement)
        } while !model.isSettled && elapsed < 10
        return (peak, elapsed, model)
    }

    func testRestStateIsTheRigidFrame() {
        let model = WobblyModel(size: SIMD2(800, 500), origin: SIMD2(10, 20))
        XCTAssertEqual(model.maxDisplacement, 0, accuracy: 1e-3)
        XCTAssertEqual(model.point(u: 1, v: 1).x, 810, accuracy: 1e-3)
        XCTAssertEqual(model.point(u: 0.5, v: 0.5).y, 270, accuracy: 1e-3)
        for _ in 0..<240 { model.step(frame) }
        XCTAssertTrue(model.isSettled)
        XCTAssertEqual(model.maxDisplacement, 0, accuracy: 1e-3)
    }

    func testDragSettlesAtTheDropPointForEveryPreset() {
        for settings in presets {
            let result = simulateDrag(settings, delta: SIMD2(500, 120), duration: 0.4)
            print("\(settings): peak \(result.peak) pt, settles in \(result.settle) s")
            XCTAssertTrue(result.model.isSettled, "does not settle: \(settings)")
            XCTAssertLessThan(result.settle, 4)
            XCTAssertGreaterThan(result.peak, 5, "barely noticeable: \(settings)")
            XCTAssertLessThan(result.model.maxDisplacement, 1, "stays deformed: \(settings)")
            XCTAssertTrue(result.model.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        }
    }

    func testWorldFrictionLeavesATrailWhileDragging() {
        // The Compiz signature: at constant speed the window trails stretched behind the cursor.
        var origin = SIMD2<Float>(0, 0)
        let grabLocal = SIMD2<Float>(450, 10)
        let model = WobblyModel(size: SIMD2(900, 600), origin: origin)
        model.grab(at: origin + grabLocal)
        for _ in 0..<240 {
            origin += SIMD2(1200, 0) * frame
            model.moveGrab(to: origin + grabLocal, origin: origin)
            model.step(frame)
        }
        let trail = model.displacement(u: 0.5, v: 1)
        XCTAssertLessThan(trail.x, -10, "the bottom edge should lag behind")
        XCTAssertTrue(trail.x.isFinite)
    }

    func testMaximizeAndUnmaximizeBounceAndSettle() {
        for settings in presets {
            for maximize in [true, false] {
                let model = WobblyModel(size: SIMD2(1440, 860), origin: SIMD2(0, 38), settings: settings)
                if maximize { model.maximize() } else { model.unmaximize() }
                var peak: Float = 0
                var elapsed: Float = 0
                repeat {
                    model.step(frame)
                    elapsed += frame
                    peak = max(peak, model.maxDisplacement)
                } while !model.isSettled && elapsed < 10
                print("\(maximize ? "maximize" : "unmaximize") \(settings): peak \(peak) pt in \(elapsed) s")
                XCTAssertTrue(model.isSettled)
                XCTAssertGreaterThan(peak, 5)
                XCTAssertLessThan(model.maxDisplacement, 1)
            }
        }
    }

    func testHigherSpeedupFactorIsSlower() {
        XCTAssertGreaterThan(WobblySettings.subtle.stepsPerSecond, WobblySettings.extreme.stepsPerSecond)
        XCTAssertEqual(WobblySettings.realistic.stepsPerSecond, 1000 / 12 + 30, accuracy: 1e-3)
    }

    func testVertexGridHonoursTilesAndMargin() {
        let model = WobblyModel(size: SIMD2(400, 200), origin: SIMD2(100, 100))
        var vertices: [SIMD4<Float>] = []
        model.fillVertices(tilesX: 16, tilesY: 14, margin: 40, into: &vertices)
        XCTAssertEqual(vertices.count, 17 * 15)
        XCTAssertEqual(vertices.first!.x, 60, accuracy: 1e-3)
        XCTAssertEqual(vertices.last!.y, 340, accuracy: 1e-3)
    }

    func testResizeBounceKeepsThePickupRowStillAndEnds() {
        let bounce = ResizeBounce(
            size: SIMD2(800, 600), origin: SIMD2(0, 0), edges: [.right],
            pickup: SIMD2(800, 300), pointerTravel: SIMD2(200, 0), settings: .realistic)
        var peak: Float = 0
        var elapsed: Float = 0
        while !bounce.isSettled {
            bounce.step(frame)
            elapsed += frame
            XCTAssertEqual(bounce.displacement(u: 1, v: 0.5).x, 0, accuracy: 1e-3)
            peak = max(peak, abs(bounce.displacement(u: 1, v: 0).x))
        }
        print("resize bounce: peak \(peak) pt")
        XCTAssertEqual(elapsed, 1, accuracy: 0.02)
        XCTAssertGreaterThan(peak, 10)
        XCTAssertEqual(bounce.maxDisplacement, 0, accuracy: 1)
    }

    func testResizeEdgesDetection() {
        let old = (minX: Float(0), minY: Float(0), maxX: Float(800), maxY: Float(600))
        XCTAssertEqual(ResizeEdges.between(old, (0, 0, 900, 600)), [.right])
        XCTAssertEqual(ResizeEdges.between(old, (-50, 0, 800, 650)), [.left, .bottom])
        XCTAssertNil(ResizeEdges.between(old, (10, 0, 810, 600)), "that's a move, not a resize")
        XCTAssertNil(ResizeEdges.between(old, old))
    }
}
