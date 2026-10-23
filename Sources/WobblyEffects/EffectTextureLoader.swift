// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import Metal

/// Loads the effect textures. Their channels hold data (shard ids, claw timings, brush strokes…), not colors,
/// so they are read exactly as stored: no premultiplication and no color conversion.
public enum EffectTextureLoader {
    public static func load(_ texture: EffectTexture, device: MTLDevice) throws -> MTLTexture {
        let url = try EffectResources.url(texture.rawValue, extension: "png", directory: "Textures")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            throw EffectError.textureDecoding(texture.rawValue)
        }
        let rgba = try pixels(of: image, bytes: bytes)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: image.width, height: image.height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let metalTexture = device.makeTexture(descriptor: descriptor) else {
            throw EffectError.textureDecoding("\(texture.rawValue): no GPU texture")
        }
        metalTexture.replace(region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0,
                             withBytes: rgba, bytesPerRow: image.width * 4)
        return metalTexture
    }

    /// Converts the decoded rows to tightly packed RGBA8.
    static func pixels(of image: CGImage, bytes: UnsafePointer<UInt8>) throws -> [UInt8] {
        let width = image.width, height = image.height
        guard image.bitsPerComponent == 8 else {
            throw EffectError.textureDecoding("only 8-bit textures are supported")
        }
        let components = image.bitsPerPixel / 8
        let alpha = image.alphaInfo
        let alphaFirst = alpha == .first || alpha == .premultipliedFirst || alpha == .noneSkipFirst
        let hasAlpha = alpha == .first || alpha == .last || alpha == .premultipliedFirst || alpha == .premultipliedLast
        guard (1...4).contains(components), !(alpha == .premultipliedFirst || alpha == .premultipliedLast) else {
            throw EffectError.textureDecoding("unsupported pixel layout (\(components) components, alpha \(alpha.rawValue))")
        }

        var out = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let row = bytes + y * image.bytesPerRow
            for x in 0..<width {
                let p = row + x * components
                var r = p[0], g = p[0], b = p[0], a: UInt8 = 255
                switch components {
                case 1: break
                case 2: a = p[1]
                case 3: (r, g, b) = (p[0], p[1], p[2])
                default:
                    if alphaFirst {
                        (a, r, g, b) = (p[0], p[1], p[2], p[3])
                    } else {
                        (r, g, b) = (p[0], p[1], p[2])
                        a = hasAlpha ? p[3] : 255
                    }
                }
                let o = (y * width + x) * 4
                out[o] = r; out[o + 1] = g; out[o + 2] = b; out[o + 3] = a
            }
        }
        return out
    }
}
