// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Metal
import simd

/// Mirror of `FXUniforms` in `common.metal`.
struct FXUniforms {
    var quadOrigin: SIMD2<Float>
    var quadSize: SIMD2<Float>
    var screenOrigin: SIMD2<Float>
    var screenSize: SIMD2<Float>
    var texSize: SIMD2<Float>
    var windowSize: SIMD2<Float>
    var uvScale: SIMD2<Float>
    var uvOffset: SIMD2<Float>
    var padding: Float
    var progress: Float
    var duration: Float
    var forOpening: Float
    var isFullscreen: Float
    var shadow: Float
    var reserved: SIMD2<Float> = .zero
}

/// Draws `EffectScene`s with the Metal shaders. One pipeline per effect, compiled on first use.
/// `prepare(_:)` may be called from a background thread while the main thread draws other effects.
public final class CloseEffectRenderer: @unchecked Sendable {
    /// Parameter slots available to a shader.
    static let maxParameters = 24

    public let device: MTLDevice
    private let lock = NSLock()
    private var pipelines: [CloseEffect: MTLRenderPipelineState] = [:]
    private var textures: [EffectTexture: MTLTexture] = [:]
    private var placeholder: MTLTexture?
    private let pixelFormat: MTLPixelFormat

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        self.device = device
        self.pixelFormat = pixelFormat
    }

    /// Compiles the shader of `effect` now, so the first frame of an animation doesn't stall.
    public func prepare(_ effect: CloseEffect) throws {
        _ = try pipeline(for: effect)
        if let texture = effect.texture { _ = try auxiliaryTexture(texture) }
    }

    private func pipeline(for effect: CloseEffect) throws -> MTLRenderPipelineState {
        lock.lock()
        let cached = pipelines[effect]
        lock.unlock()
        if let cached { return cached }

        // Compiled outside the lock: a background warm-up must not stall the frame being drawn.
        let options = MTLCompileOptions()
        options.fastMathEnabled = false
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: EffectShaderSource.source(for: effect), options: options)
        } catch let error as EffectError {
            throw error
        } catch {
            throw EffectError.compilation("\(effect.shaderName): \(error)")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "fxVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "fxFragment")
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = pixelFormat
        color.isBlendingEnabled = true
        color.rgbBlendOperation = .add
        color.alphaBlendOperation = .add
        // The shader outputs premultiplied alpha.
        color.sourceRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        let state = try device.makeRenderPipelineState(descriptor: descriptor)
        lock.lock()
        pipelines[effect] = state
        lock.unlock()
        return state
    }

    private func auxiliaryTexture(_ kind: EffectTexture) throws -> MTLTexture {
        lock.lock()
        let cached = textures[kind]
        lock.unlock()
        if let cached { return cached }

        let texture = try EffectTextureLoader.load(kind, device: device)
        lock.lock()
        textures[kind] = texture
        lock.unlock()
        return texture
    }

    private func placeholderTexture() -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        if let placeholder { return placeholder }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        placeholder = device.makeTexture(descriptor: descriptor)
        return placeholder
    }

    /// Encodes the draw call of `scene` into a pass that renders the screen whose global rectangle is `screenRect`.
    /// Returns false if the effect can't be drawn (its shader failed to compile).
    @discardableResult
    public func encode(_ scene: EffectScene, into encoder: MTLRenderCommandEncoder, screenRect: CGRect) -> Bool {
        guard let state = try? pipeline(for: scene.effect),
              let auxiliary = try? scene.effect.texture.map(auxiliaryTexture) ?? placeholderTexture() else { return false }

        let quad = scene.quadRect
        let windowSize = SIMD2(Float(scene.windowFrame.width), Float(scene.windowFrame.height))
        var uniforms = FXUniforms(
            quadOrigin: SIMD2(Float(quad.minX), Float(quad.minY)), quadSize: SIMD2(Float(quad.width), Float(quad.height)),
            screenOrigin: SIMD2(Float(screenRect.minX), Float(screenRect.minY)),
            screenSize: SIMD2(Float(screenRect.width), Float(screenRect.height)),
            texSize: windowSize + 2 * scene.padding, windowSize: windowSize,
            uvScale: scene.uvScale, uvOffset: scene.uvOffset, padding: scene.padding,
            progress: min(max(scene.progress, 0), 1), duration: scene.duration, forOpening: 0, isFullscreen: 0,
            shadow: scene.shadowOpacity)

        var slots = [SIMD4<Float>](repeating: .zero, count: Self.maxParameters)
        for (index, parameter) in scene.parameters.prefix(Self.maxParameters).enumerated() {
            slots[index] = parameter.value
        }

        encoder.setRenderPipelineState(state)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<FXUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FXUniforms>.stride, index: 0)
        encoder.setFragmentBytes(slots, length: MemoryLayout<SIMD4<Float>>.stride * slots.count, index: 1)
        encoder.setFragmentTexture(scene.texture, index: 0)
        encoder.setFragmentTexture(auxiliary, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        return true
    }
}
