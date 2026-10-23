// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import simd

/// One effect uniform. Every parameter occupies one `float4` slot of the parameter buffer, and the shader
/// reads it through a macro generated from `name` (so `uScale` in the Metal source is `P[3].x`).
public struct EffectParameter: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case float, vec2, vec3, vec4, bool
    }

    public let name: String
    public let kind: Kind
    public let value: SIMD4<Float>

    public init(name: String, kind: Kind, value: SIMD4<Float>) {
        self.name = name
        self.kind = kind
        self.value = value
    }

    /// Metal expression that reads this parameter from `slot` of the `P` buffer.
    func accessor(slot: Int) -> String {
        switch kind {
        case .float: return "(P[\(slot)].x)"
        case .vec2: return "(P[\(slot)].xy)"
        case .vec3: return "(P[\(slot)].xyz)"
        case .vec4: return "(P[\(slot)])"
        case .bool: return "(P[\(slot)].x > 0.5)"
        }
    }

    static func float(_ name: String, _ x: Float) -> EffectParameter {
        EffectParameter(name: name, kind: .float, value: SIMD4(x, 0, 0, 0))
    }

    static func vec2(_ name: String, _ x: Float, _ y: Float) -> EffectParameter {
        EffectParameter(name: name, kind: .vec2, value: SIMD4(x, y, 0, 0))
    }

    static func vec2(_ name: String, _ v: SIMD2<Float>) -> EffectParameter {
        vec2(name, v.x, v.y)
    }

    static func vec3(_ name: String, _ v: SIMD3<Float>) -> EffectParameter {
        EffectParameter(name: name, kind: .vec3, value: SIMD4(v.x, v.y, v.z, 0))
    }

    static func vec4(_ name: String, _ x: Float, _ y: Float, _ z: Float, _ w: Float) -> EffectParameter {
        EffectParameter(name: name, kind: .vec4, value: SIMD4(x, y, z, w))
    }

    static func bool(_ name: String, _ on: Bool) -> EffectParameter {
        EffectParameter(name: name, kind: .bool, value: SIMD4(on ? 1 : 0, 0, 0, 0))
    }

    /// Color given as 0–255 components, like the settings of Burn-My-Windows.
    static func rgb(_ name: String, _ r: Float, _ g: Float, _ b: Float) -> EffectParameter {
        vec3(name, SIMD3(r, g, b) / 255)
    }

    static func rgba(_ name: String, _ r: Float, _ g: Float, _ b: Float, _ a: Float) -> EffectParameter {
        vec4(name, r / 255, g / 255, b / 255, a)
    }
}

/// Small deterministic generator: the same seed gives the same animation, which the tests rely on.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// What an effect needs to know about the window it plays on.
public struct EffectContext: Sendable {
    /// Size of the window itself, in points.
    public var windowSize: SIMD2<Float>
    /// Transparent border around the window in the capture (its shadow), in points.
    public var padding: Float
    /// Height of the screen the window is on, in points (Doom needs it to cover the whole screen).
    public var screenHeight: Float
    /// Pointer position relative to the window and its padding, in [0, 1]² (Incinerate, Pixel Wipe, Broken Glass).
    public var pointer: SIMD2<Float>
    /// System accent color, used by Materialize.
    public var accentColor: SIMD3<Float>
    public var generator: SplitMix64

    public init(windowSize: SIMD2<Float>, padding: Float = 0, screenHeight: Float = 1080,
                pointer: SIMD2<Float> = SIMD2(0.5, 0.5),
                accentColor: SIMD3<Float> = SIMD3(130, 190, 60) / 255,
                seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        self.windowSize = windowSize
        self.padding = padding
        self.screenHeight = screenHeight
        self.pointer = pointer
        self.accentColor = accentColor
        generator = SplitMix64(seed: seed)
    }

    /// Size of the effect's actor: the window plus its padding.
    public var actorSize: SIMD2<Float> { windowSize + 2 * padding }

    public mutating func random() -> Float {
        Float.random(in: 0..<1, using: &generator)
    }

    mutating func randomPair() -> SIMD2<Float> {
        SIMD2(random(), random())
    }
}
