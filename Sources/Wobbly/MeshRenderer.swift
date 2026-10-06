// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreVideo
import Metal
import MetalKit
import WobblyCore

private let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 origin;
    float2 size;
    float2 windowSize;
    float2 offset;
    float cornerRadius;
    float shadowOpacity;
    float shadowBlur;
    float alpha;
};

struct VOut {
    float4 position [[position]];
    float2 uv;
};

vertex VOut meshVertex(uint vid [[vertex_id]],
                       const device float4 *vertices [[buffer(0)]],
                       constant Uniforms &u [[buffer(1)]]) {
    float4 v = vertices[vid];
    float2 p = (v.xy + u.offset - u.origin) / u.size;
    VOut out;
    out.position = float4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);
    out.uv = v.zw;
    return out;
}

fragment float4 windowFragment(VOut in [[stage_in]],
                               texture2d<float> texture [[texture(0)]],
                               constant Uniforms &u [[buffer(1)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    return texture.sample(s, in.uv) * u.alpha;
}

fragment float4 shadowFragment(VOut in [[stage_in]], constant Uniforms &u [[buffer(1)]]) {
    float2 halfSize = u.windowSize * 0.5;
    float2 q = abs(in.uv * u.windowSize - halfSize) - (halfSize - u.cornerRadius);
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - u.cornerRadius;
    float a = 1.0 - smoothstep(-u.shadowBlur * 0.35, u.shadowBlur, d);
    return float4(0.0, 0.0, 0.0, a * a * u.shadowOpacity * u.alpha);
}
"""

private struct Uniforms {
    var origin: SIMD2<Float>
    var size: SIMD2<Float>
    var windowSize: SIMD2<Float>
    var offset: SIMD2<Float>
    var cornerRadius: Float
    var shadowOpacity: Float
    var shadowBlur: Float
    var alpha: Float
}

/// Draws the window capture onto the deformed mesh, plus a shadow that deforms along with it.
/// All overlays (one per screen) share the same scene.
@MainActor
final class MeshRenderer {
    static let shadowMargin: Float = 48

    let device: MTLDevice
    var shadowEnabled = true
    private(set) var hasScene = false
    /// Bounding box of the scene (shadow included), in global CG coordinates.
    private(set) var sceneBounds = CGRect.null

    private let queue: MTLCommandQueue
    private let windowPipeline: MTLRenderPipelineState
    private let shadowPipeline: MTLRenderPipelineState
    private var indexBuffer: MTLBuffer?
    private var indexCount = 0
    private var tiles = (x: 0, y: 0)
    private var textureCache: CVMetalTextureCache?
    private var texture: MTLTexture?
    private var cvTexture: CVMetalTexture?
    private var windowSize = SIMD2<Float>.zero
    private var windowVertices: [SIMD4<Float>] = []
    private var shadowVertices: [SIMD4<Float>] = []
    private var windowBuffer: MTLBuffer?
    private var shadowBuffer: MTLBuffer?

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            func pipeline(_ fragment: String) throws -> MTLRenderPipelineState {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "meshVertex")
                descriptor.fragmentFunction = library.makeFunction(name: fragment)
                let color = descriptor.colorAttachments[0]!
                color.pixelFormat = .bgra8Unorm
                color.isBlendingEnabled = true
                color.rgbBlendOperation = .add
                color.alphaBlendOperation = .add
                color.sourceRGBBlendFactor = .one
                color.sourceAlphaBlendFactor = .one
                color.destinationRGBBlendFactor = .oneMinusSourceAlpha
                color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                return try device.makeRenderPipelineState(descriptor: descriptor)
            }
            windowPipeline = try pipeline("windowFragment")
            shadowPipeline = try pipeline("shadowFragment")
        } catch {
            NSLog("Wobbly: failed to compile shaders: \(error)")
            return nil
        }

        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    /// Triangles for the (tilesX + 1) × (tilesY + 1) vertex grid; rebuilt only when the tiles change.
    private func prepareIndices(tilesX: Int, tilesY: Int) {
        guard tiles != (tilesX, tilesY) else { return }
        var indices: [UInt16] = []
        indices.reserveCapacity(tilesX * tilesY * 6)
        for j in 0..<tilesY {
            for i in 0..<tilesX {
                let a = UInt16(j * (tilesX + 1) + i)
                let b = a + 1
                let c = a + UInt16(tilesX + 1)
                let d = c + 1
                indices += [a, b, c, b, d, c]
            }
        }
        indexBuffer = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.stride)
        indexCount = indices.count
        tiles = (tilesX, tilesY)
    }

    /// Wraps the capture's IOSurface in a texture without copying it.
    func setFrame(_ frame: CapturedFrame) -> Bool {
        guard let textureCache else { return false }
        let pixelBuffer = frame.pixelBuffer
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, pixelBuffer, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer), 0, &cvTexture)
        guard status == kCVReturnSuccess, let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { return false }
        self.cvTexture = cvTexture
        self.texture = texture
        windowSize = SIMD2(Float(frame.pointSize.width), Float(frame.pointSize.height))
        return true
    }

    func update(from deformer: WindowDeformer, tilesX: Int, tilesY: Int) {
        prepareIndices(tilesX: tilesX, tilesY: tilesY)
        deformer.fillVertices(tilesX: tilesX, tilesY: tilesY, into: &windowVertices)
        deformer.fillVertices(tilesX: tilesX, tilesY: tilesY, margin: Self.shadowMargin, into: &shadowVertices)
        let length = windowVertices.count * MemoryLayout<SIMD4<Float>>.stride
        // Fresh buffers every frame: the GPU may still be reading the previous frame's.
        windowBuffer = device.makeBuffer(bytes: windowVertices, length: length, options: .storageModeShared)
        shadowBuffer = device.makeBuffer(bytes: shadowVertices, length: length, options: .storageModeShared)

        var minP = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
        var maxP = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
        for v in shadowVertices {
            minP = simd_min(minP, SIMD2(v.x, v.y))
            maxP = simd_max(maxP, SIMD2(v.x, v.y))
        }
        sceneBounds = CGRect(x: CGFloat(minP.x), y: CGFloat(minP.y), width: CGFloat(maxP.x - minP.x), height: CGFloat(maxP.y - minP.y + 24))
        hasScene = texture != nil
    }

    func clearScene() {
        hasScene = false
        sceneBounds = .null
        texture = nil
        cvTexture = nil
        windowBuffer = nil
        shadowBuffer = nil
    }

    func draw(in view: MTKView, screenRect: CGRect) {
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        if hasScene, let texture, let windowBuffer, let shadowBuffer, let indexBuffer {
            var uniforms = Uniforms(
                origin: SIMD2(Float(screenRect.minX), Float(screenRect.minY)),
                size: SIMD2(Float(screenRect.width), Float(screenRect.height)),
                windowSize: windowSize,
                offset: SIMD2(0, 12),
                cornerRadius: 14,
                shadowOpacity: 0.32,
                shadowBlur: 30,
                alpha: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

            if shadowEnabled {
                encoder.setRenderPipelineState(shadowPipeline)
                encoder.setVertexBuffer(shadowBuffer, offset: 0, index: 0)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
            }

            uniforms.offset = .zero
            encoder.setRenderPipelineState(windowPipeline)
            encoder.setVertexBuffer(windowBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
