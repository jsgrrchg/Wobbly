// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Metal
import XCTest
@testable import WobblyEffects

/// Pure logic of the effect catalog.
final class CloseEffectCatalogTests: XCTestCase {
    func testThereAreThirtyEffectsWithUniqueNamesAndShaders() throws {
        XCTAssertEqual(CloseEffect.allCases.count, 30)
        XCTAssertEqual(Set(CloseEffect.allCases.map(\.title)).count, 30)
        XCTAssertEqual(Set(CloseEffect.allCases.map(\.shaderName)).count, 30)
        for effect in CloseEffect.allCases {
            XCTAssertNoThrow(try EffectResources.text(effect.shaderName), "missing shader for \(effect)")
            XCTAssertGreaterThan(effect.duration, 0)
        }
    }

    func testParametersFitTheBufferWithUniqueNames() {
        for effect in CloseEffect.allCases {
            var context = EffectContext(windowSize: SIMD2(800, 600), padding: 40, seed: 1)
            let parameters = effect.parameters(&context)
            XCTAssertLessThanOrEqual(parameters.count, CloseEffectRenderer.maxParameters, "\(effect)")
            XCTAssertEqual(Set(parameters.map(\.name)).count, parameters.count, "duplicate uniform names in \(effect)")
            XCTAssertTrue(parameters.allSatisfy { $0.name.hasPrefix("u") }, "\(effect)")
        }
    }

    func testLayoutDoesNotDependOnTheRandomSeed() {
        for effect in CloseEffect.allCases {
            var first = EffectContext(windowSize: SIMD2(800, 600), padding: 40, seed: 1)
            var second = EffectContext(windowSize: SIMD2(300, 200), padding: 10, seed: 99)
            let a = effect.parameters(&first), b = effect.parameters(&second)
            XCTAssertEqual(a.map(\.name), b.map(\.name), "\(effect)")
            XCTAssertEqual(a.map(\.kind), b.map(\.kind), "\(effect)")
        }
    }

    func testSameSeedGivesSameAnimation() {
        var first = EffectContext(windowSize: SIMD2(800, 600), seed: 7)
        var second = EffectContext(windowSize: SIMD2(800, 600), seed: 7)
        var third = EffectContext(windowSize: SIMD2(800, 600), seed: 8)
        XCTAssertEqual(CloseEffect.portal.parameters(&first), CloseEffect.portal.parameters(&second))
        XCTAssertNotEqual(CloseEffect.portal.parameters(&first), CloseEffect.portal.parameters(&third))
    }

    func testUniformStructMatchesTheMetalLayout() {
        XCTAssertEqual(MemoryLayout<FXUniforms>.size, 112)
        XCTAssertEqual(MemoryLayout<FXUniforms>.stride, 112)
    }

    func testGeneratedSourceDeclaresEveryParameter() throws {
        let source = try EffectShaderSource.source(for: .fire)
        XCTAssertTrue(source.contains("#define uScale (P[1].x)"))
        XCTAssertTrue(source.contains("#define uGradient5 (P[7])"))
        XCTAssertTrue(source.contains("fragment float4 fxFragment"))
    }

    func testActorScales() {
        let context = EffectContext(windowSize: SIMD2(800, 400), padding: 50, screenHeight: 1000)
        XCTAssertEqual(CloseEffect.apparition.actorScale(for: context), SIMD2(2, 2))
        XCTAssertEqual(CloseEffect.brokenGlass.actorScale(for: context), SIMD2(2, 2))
        XCTAssertEqual(CloseEffect.fire.actorScale(for: context), SIMD2(1, 1))
        // Doom must cover the screen height: 2 × screen / actor height.
        XCTAssertEqual(CloseEffect.doom.actorScale(for: context).y, 2 * 1000 / 500, accuracy: 1e-4)
    }

    func testChoiceRoundTrip() {
        for choice in [CloseEffectChoice.off, .random] + CloseEffect.allCases.map(CloseEffectChoice.effect) {
            XCTAssertEqual(CloseEffectChoice(rawValue: choice.rawValue), choice)
        }
        XCTAssertEqual(CloseEffectChoice(rawValue: nil), .effect(.fire))
        XCTAssertEqual(CloseEffectChoice(rawValue: "nonsense"), .effect(.fire))
    }

    func testChoiceResolution() {
        var generator = SplitMix64(seed: 3)
        XCTAssertNil(CloseEffectChoice.off.resolve(using: &generator))
        XCTAssertEqual(CloseEffectChoice.effect(.glide).resolve(using: &generator), .glide)
        let picks = Set((0..<200).compactMap { _ in CloseEffectChoice.random.resolve(using: &generator) })
        XCTAssertGreaterThan(picks.count, 20)
    }
}

/// Effects drawn on the GPU, with real textures and a window image drawn like a macOS window.
final class CloseEffectRenderTests: XCTestCase {
    private var preview: EffectPreview!

    override func setUpWithError() throws {
        preview = try EffectPreview()
    }

    func testEveryShaderCompilesAndDraws() throws {
        var failures: [String] = []
        for effect in CloseEffect.allCases {
            do {
                try preview.renderer.prepare(effect)
                let frame = try preview.render(preview.scene(for: effect), progress: 0.4)
                XCTAssertEqual(frame.pixels.count, frame.width * frame.height * 4)
            } catch {
                failures.append("\(effect.title): \(error)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "Shaders that failed:\n" + failures.joined(separator: "\n"))
    }

    /// At the start the window must look untouched, and at the end it must be gone.
    func testEffectsStartWithTheWindowAndEndWithoutIt() throws {
        for effect in CloseEffect.allCases {
            let scene = preview.scene(for: effect)
            let interior = EffectPreview.interior(of: scene)
            let start = try preview.render(scene, progress: 0).meanAlpha(in: interior)
            let end = try preview.render(scene, progress: 1).meanAlpha(in: interior)
            XCTAssertGreaterThan(start, 0.85, "\(effect.title) doesn't show the window at progress 0")
            if effect.vanishesCompletely {
                XCTAssertLessThan(end, 0.2, "\(effect.title) leaves the window visible at progress 1")
            }
        }
    }

    /// The window must go away monotonically enough: halfway through there is still something, but less than at the start.
    func testWindowFadesOverTheAnimation() throws {
        for effect in CloseEffect.allCases where effect.vanishesCompletely {
            let scene = preview.scene(for: effect)
            let interior = EffectPreview.interior(of: scene)
            let middle = try preview.render(scene, progress: 0.6).meanAlpha(in: interior)
            let late = try preview.render(scene, progress: 0.95).meanAlpha(in: interior)
            XCTAssertLessThanOrEqual(late, middle + 0.05, "\(effect.title) reappears at the end")
        }
    }

    func testSameSeedRendersTheSameFrame() throws {
        for effect in [CloseEffect.incinerate, .brokenGlass, .snapOfDisintegration] {
            let a = try preview.render(preview.scene(for: effect, seed: 5), progress: 0.5)
            let b = try preview.render(preview.scene(for: effect, seed: 5), progress: 0.5)
            let c = try preview.render(preview.scene(for: effect, seed: 6), progress: 0.5)
            XCTAssertEqual(a.pixels, b.pixels, "\(effect.title) isn't deterministic")
            XCTAssertNotEqual(a.pixels, c.pixels, "\(effect.title) ignores its seed")
        }
    }
}

final class EffectSceneTests: XCTestCase {
    private func makeTexture() throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(), "no Metal device")
        return try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    }

    func testQuadIsCenteredOnTheWindow() throws {
        let frame = CGRect(x: 100, y: 50, width: 400, height: 300)
        let scene = EffectScene(
            effect: .apparition, texture: try makeTexture(), uvScale: SIMD2(1, 1), uvOffset: .zero, windowFrame: frame,
            padding: 20, pointer: CGPoint(x: 120, y: 60), screenHeight: 900, accentColor: SIMD3(1, 1, 1), durationScale: 2)
        // Apparition doubles the 440 × 340 actor.
        XCTAssertEqual(scene.quadRect.width, 880, accuracy: 0.01)
        XCTAssertEqual(scene.quadRect.height, 680, accuracy: 0.01)
        XCTAssertEqual(scene.quadRect.midX, frame.midX, accuracy: 0.01)
        XCTAssertEqual(scene.quadRect.midY, frame.midY, accuracy: 0.01)
        XCTAssertEqual(scene.duration, Float(CloseEffect.apparition.duration) * 2, accuracy: 1e-4)
    }

    func testPointerIsRelativeToTheWindowAndClamped() throws {
        let texture = try makeTexture()
        let frame = CGRect(x: 100, y: 50, width: 400, height: 300)
        func startPos(_ pointer: CGPoint) -> SIMD2<Float> {
            let scene = EffectScene(
                effect: .pixelWipe, texture: texture, uvScale: SIMD2(1, 1), uvOffset: .zero, windowFrame: frame, padding: 0,
                pointer: pointer, screenHeight: 900, accentColor: SIMD3(1, 1, 1))
            return scene.parameters.first { $0.name == "uStartPos" }!.value.xy
        }
        XCTAssertEqual(startPos(CGPoint(x: 300, y: 200)), SIMD2(0.5, 0.5))
        XCTAssertEqual(startPos(CGPoint(x: -500, y: 9000)), SIMD2(0, 1))
    }
}

/// The effect textures hold data in their channels, so they must be read exactly as stored.
final class EffectTextureTests: XCTestCase {
    private func load(_ kind: EffectTexture) throws -> (texture: MTLTexture, bytes: [UInt8]) {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(), "no Metal device")
        let texture = try EffectTextureLoader.load(kind, device: device)
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(&bytes, bytesPerRow: texture.width * 4, from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        return (texture, bytes)
    }

    private func pixel(_ image: (texture: MTLTexture, bytes: [UInt8]), _ x: Int, _ y: Int) -> [UInt8] {
        let o = (y * image.texture.width + x) * 4
        return Array(image.bytes[o..<o + 4])
    }

    /// Reference values read with an independent decoder (Pillow). The brush stores data in its alpha channel:
    /// it must not be premultiplied into the color channels.
    func testChannelsAreReadAsStored() throws {
        let brush = try load(.brush)
        XCTAssertEqual([brush.texture.width, brush.texture.height], [1024, 1024])
        XCTAssertEqual(pixel(brush, 512, 512), [76, 63, 106, 72])
        XCTAssertEqual(pixel(brush, 300, 700), [112, 100, 116, 166])
        XCTAssertEqual(pixel(brush, 900, 100), [22, 32, 58, 93])

        let font = try load(.matrixFont)
        XCTAssertEqual(pixel(font, 40, 40), [188, 188, 188, 255])
        XCTAssertEqual(pixel(font, 100, 200), [22, 22, 22, 255])

        let claws = try load(.claws)
        XCTAssertEqual(pixel(claws, 400, 400), [22, 22, 22, 255])
        XCTAssertEqual(pixel(claws, 100, 50), [255, 255, 255, 255])

        let shards = try load(.shards)
        XCTAssertEqual(pixel(shards, 10, 10), [74, 80, 1, 255])
        XCTAssertEqual(pixel(shards, 256, 256), [133, 41, 0, 255])

        let dust = try load(.dust)
        XCTAssertEqual(pixel(dust, 100, 100), [84, 209, 0, 255])
        XCTAssertEqual(pixel(dust, 400, 30), [101, 141, 1, 255])
    }
}
