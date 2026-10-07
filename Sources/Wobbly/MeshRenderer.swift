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
    float2 uvScale;
    float2 uvOffset;
    float shadow;
};

struct VOut {
    float4 position [[position]];
    float2 uv;
};

vertex VOut meshVertex(uint vid [[vertex_id]],
                       const device float4 *vertices [[buffer(0)]],
                       constant Uniforms &u [[buffer(1)]]) {
    float4 v = vertices[vid];
    float2 p = (v.xy - u.origin) / u.size;
    VOut out;
    out.position = float4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);
    out.uv = v.zw;
    return out;
}

// `uv` is relative to the window ([0, 1]² is the window, the rest its shadow); the texture holds both.
fragment float4 windowFragment(VOut in [[stage_in]],
                               texture2d<float> texture [[texture(0)]],
                               constant Uniforms &u [[buffer(1)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    bool inShadow = any(in.uv < 0.0) || any(in.uv > 1.0);
    if (inShadow && u.shadow == 0.0) { return float4(0.0); }
    return texture.sample(s, in.uv * u.uvScale + u.uvOffset);
}
"""

private struct Uniforms {
    var origin: SIMD2<Float>
    var size: SIMD2<Float>
    var uvScale: SIMD2<Float>
    var uvOffset: SIMD2<Float>
    var shadow: Float
}

/// Draws the window capture, native shadow included, onto the deformed mesh: the shadow sits on an outer
/// ring of the mesh, so it deforms along with the window. All overlays (one per screen) share the same scene.
@MainActor
final class MeshRenderer {
    let device: MTLDevice
    /// Off while the real window (with its own shadow) is still underneath, so the two don't add up.
    var shadowEnabled = true
    private(set) var hasScene = false
    /// Bounding box of the scene (shadow included), in global CG coordinates.
    private(set) var sceneBounds = CGRect.null

    private let queue: MTLCommandQueue
    private let windowPipeline: MTLRenderPipelineState
    private var indexBuffer: MTLBuffer?
    private var indexCount = 0
    private var tiles = (x: 0, y: 0)
    private var textureCache: CVMetalTextureCache?
    private var texture: MTLTexture?
    private var cvTexture: CVMetalTexture?
    private var uvScale = SIMD2<Float>(repeating: 1)
    private var uvOffset = SIMD2<Float>.zero
    private var shadowInsets = ShadowInsets()
    private var vertices: [SIMD4<Float>] = []
    private var vertexBuffer: MTLBuffer?

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "meshVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "windowFragment")
            let color = descriptor.colorAttachments[0]!
            color.pixelFormat = .bgra8Unorm
            color.isBlendingEnabled = true
            color.rgbBlendOperation = .add
            color.alphaBlendOperation = .add
            color.sourceRGBBlendFactor = .one
            color.sourceAlphaBlendFactor = .one
            color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            windowPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
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
        let bufferSize = SIMD2(Float(CVPixelBufferGetWidth(pixelBuffer)), Float(CVPixelBufferGetHeight(pixelBuffer)))
        uvScale = SIMD2(Float(frame.windowRect.width), Float(frame.windowRect.height)) / bufferSize
        uvOffset = SIMD2(Float(frame.windowRect.minX), Float(frame.windowRect.minY)) / bufferSize
        shadowInsets = frame.shadow
        return true
    }

    func update(from deformer: WindowDeformer, tilesX: Int, tilesY: Int) {
        // The shadow ring adds a row and a column of tiles on each side.
        prepareIndices(tilesX: tilesX + 2, tilesY: tilesY + 2)
        let outset = (Float(shadowInsets.left), Float(shadowInsets.top), Float(shadowInsets.right), Float(shadowInsets.bottom))
        deformer.fillVertices(tilesX: tilesX, tilesY: tilesY, outset: outset, into: &vertices)
        // A fresh buffer every frame: the GPU may still be reading the previous frame's.
        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<SIMD4<Float>>.stride,
                                         options: .storageModeShared)

        var minP = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
        var maxP = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
        for v in vertices {
            minP = simd_min(minP, SIMD2(v.x, v.y))
            maxP = simd_max(maxP, SIMD2(v.x, v.y))
        }
        sceneBounds = CGRect(x: CGFloat(minP.x), y: CGFloat(minP.y), width: CGFloat(maxP.x - minP.x), height: CGFloat(maxP.y - minP.y))
        hasScene = texture != nil
    }

    func clearScene() {
        hasScene = false
        sceneBounds = .null
        texture = nil
        cvTexture = nil
        vertexBuffer = nil
    }

    func draw(in view: MTKView, screenRect: CGRect) {
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        if hasScene, let texture, let vertexBuffer, let indexBuffer {
            var uniforms = Uniforms(
                origin: SIMD2(Float(screenRect.minX), Float(screenRect.minY)),
                size: SIMD2(Float(screenRect.width), Float(screenRect.height)),
                uvScale: uvScale,
                uvOffset: uvOffset,
                shadow: shadowEnabled ? 1 : 0)
            encoder.setRenderPipelineState(windowPipeline)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
