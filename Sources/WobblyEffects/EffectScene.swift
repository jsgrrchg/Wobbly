// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Metal
import simd

/// One window being closed with an effect: the frozen capture of the window plus everything the shader needs.
public struct EffectScene {
    public let effect: CloseEffect
    /// Premultiplied capture of the window and its shadow.
    public let texture: MTLTexture
    /// Window-relative uv → capture uv (the capture holds the window at an offset, with its shadow around it).
    public let uvScale: SIMD2<Float>
    public let uvOffset: SIMD2<Float>
    /// The window in global CoreGraphics coordinates.
    public let windowFrame: CGRect
    /// Transparent margin around the window in the capture (its shadow), in points.
    public let padding: Float
    /// Animation time in seconds.
    public let duration: Float
    public let parameters: [EffectParameter]
    public let actorScale: SIMD2<Float>
    /// 0 at the first frame, 1 when the window is gone.
    public var progress: Float = 0
    /// Opacity of the window's shadow in the capture: 0 while the real window, and its own shadow, is still there.
    public var shadowOpacity: Float = 1

    /// - Parameters:
    ///   - pointer: Pointer position in global coordinates (some effects start from it).
    ///   - durationScale: Multiplies the effect's default animation time.
    public init(effect: CloseEffect, texture: MTLTexture, uvScale: SIMD2<Float>, uvOffset: SIMD2<Float>,
                windowFrame: CGRect, padding: Float, pointer: CGPoint, screenHeight: Float,
                accentColor: SIMD3<Float>, durationScale: Float = 1, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        let size = SIMD2(Float(windowFrame.width), Float(windowFrame.height))
        let actor = size + 2 * padding
        let pointerUV = SIMD2(
            Float(pointer.x - windowFrame.minX) + padding, Float(pointer.y - windowFrame.minY) + padding) / actor
        var context = EffectContext(
            windowSize: size, padding: padding, screenHeight: screenHeight,
            pointer: simd_clamp(pointerUV, SIMD2(repeating: 0), SIMD2(repeating: 1)), accentColor: accentColor, seed: seed)
        self.effect = effect
        self.texture = texture
        self.uvScale = uvScale
        self.uvOffset = uvOffset
        self.windowFrame = windowFrame
        self.padding = padding
        duration = Float(effect.duration) * max(durationScale, 0.05)
        actorScale = effect.actorScale(for: context)
        parameters = effect.parameters(&context)
    }

    /// Where the effect draws, in global coordinates: the window with its padding, scaled around its center.
    public var quadRect: CGRect {
        let size = SIMD2(Float(windowFrame.width), Float(windowFrame.height)) + 2 * padding
        let scaled = size * actorScale
        return CGRect(x: windowFrame.midX - CGFloat(scaled.x) / 2, y: windowFrame.midY - CGFloat(scaled.y) / 2,
                      width: CGFloat(scaled.x), height: CGFloat(scaled.y))
    }
}
