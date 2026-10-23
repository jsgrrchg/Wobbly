// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The effects and their default settings come from Burn-My-Windows by Simon Schneegans
// (https://github.com/Schneegans/Burn-My-Windows, GPL-3.0-or-later). The shaders were ported from GLSL
// to Metal; see NOTICE.

import Foundation
import simd

/// Texture an effect samples besides the window capture.
public enum EffectTexture: String, Sendable, CaseIterable {
    case brush, claws, dust, matrixFont, shards
}

/// The window-close effects of Burn-My-Windows.
public enum CloseEffect: String, CaseIterable, Sendable, Identifiable {
    case aperturePanels, apparition, auraGlow, brokenGlass, doom, energizeA, energizeB, fire, focus, glide
    case glitch, hexagon, incinerate, materialize, matrix, morph, mushroom, paintBrush, pixelate, pixelWheel
    case pixelWipe, portal, rgbWarp, snapOfDisintegration, teamRocket, tRexAttack, tvEffect, tvGlitch, wisps, wormhole

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .aperturePanels: return "Aperture Panels"
        case .apparition: return "Apparition"
        case .auraGlow: return "Aura Glow"
        case .brokenGlass: return "Broken Glass"
        case .doom: return "Doom"
        case .energizeA: return "Energize A"
        case .energizeB: return "Energize B"
        case .fire: return "Fire"
        case .focus: return "Focus"
        case .glide: return "Glide"
        case .glitch: return "Glitch"
        case .hexagon: return "Hexagon"
        case .incinerate: return "Incinerate"
        case .materialize: return "Materialize"
        case .matrix: return "Matrix"
        case .morph: return "Morph"
        case .mushroom: return "Mushroom"
        case .paintBrush: return "Paint Brush"
        case .pixelate: return "Pixelate"
        case .pixelWheel: return "Pixel Wheel"
        case .pixelWipe: return "Pixel Wipe"
        case .portal: return "Portal"
        case .rgbWarp: return "RGB Warp"
        case .snapOfDisintegration: return "Snap of Disintegration"
        case .teamRocket: return "Team Rocket"
        case .tRexAttack: return "T-Rex Attack"
        case .tvEffect: return "TV Effect"
        case .tvGlitch: return "TV Glitch"
        case .wisps: return "Wisps"
        case .wormhole: return "Wormhole"
        }
    }

    /// Name of the Metal source file (without extension) in `Resources/Shaders`.
    var shaderName: String {
        switch self {
        case .aperturePanels: return "aperture-panels"
        case .apparition: return "apparition"
        case .auraGlow: return "aura-glow"
        case .brokenGlass: return "broken-glass"
        case .doom: return "doom"
        case .energizeA: return "energize-a"
        case .energizeB: return "energize-b"
        case .fire: return "fire"
        case .focus: return "focus"
        case .glide: return "glide"
        case .glitch: return "glitch"
        case .hexagon: return "hexagon"
        case .incinerate: return "incinerate"
        case .materialize: return "materialize"
        case .matrix: return "matrix"
        case .morph: return "morph"
        case .mushroom: return "mushroom"
        case .paintBrush: return "paint-brush"
        case .pixelate: return "pixelate"
        case .pixelWheel: return "pixel-wheel"
        case .pixelWipe: return "pixel-wipe"
        case .portal: return "portal"
        case .rgbWarp: return "rgbwarp"
        case .snapOfDisintegration: return "snap"
        case .teamRocket: return "team-rocket"
        case .tRexAttack: return "trex"
        case .tvEffect: return "tv"
        case .tvGlitch: return "tv-glitch"
        case .wisps: return "wisps"
        case .wormhole: return "wormhole"
        }
    }

    /// Default animation time, in seconds.
    public var duration: TimeInterval {
        switch self {
        case .aperturePanels: return 2.0
        case .apparition: return 0.3
        case .auraGlow: return 0.75
        case .brokenGlass: return 1.0
        case .doom: return 1.0
        case .energizeA: return 2.0
        case .energizeB: return 1.0
        case .fire: return 1.5
        case .focus: return 0.5
        case .glide: return 0.25
        case .glitch: return 0.75
        case .hexagon: return 1.5
        case .incinerate: return 2.0
        case .materialize: return 0.25
        case .matrix: return 1.5
        case .morph: return 1.5
        case .mushroom: return 1.5
        case .paintBrush: return 1.0
        case .pixelate: return 0.5
        case .pixelWheel: return 0.3
        case .pixelWipe: return 1.0
        case .portal: return 1.25
        case .rgbWarp: return 0.75
        case .snapOfDisintegration: return 1.5
        case .teamRocket: return 1.5
        case .tRexAttack: return 1.0
        case .tvEffect: return 0.4
        case .tvGlitch: return 0.75
        case .wisps: return 1.5
        case .wormhole: return 2.0
        }
    }

    /// Materialize ends on a faded panel in its last step, but the last frame is never shown: the player removes the scene.
    public var vanishesCompletely: Bool { self != .materialize }

    public var texture: EffectTexture? {
        switch self {
        case .brokenGlass: return .shards
        case .matrix: return .matrixFont
        case .paintBrush: return .brush
        case .snapOfDisintegration: return .dust
        case .tRexAttack: return .claws
        default: return nil
        }
    }

    /// How much larger than the window (and its padding) the quad is, so effects can draw outside the window.
    /// The effect's [0, 1]² coordinates always cover the unscaled window, whatever the scale.
    public func actorScale(for context: EffectContext) -> SIMD2<Float> {
        switch self {
        case .apparition, .brokenGlass: return SIMD2(2, 2)
        case .doom: return SIMD2(1, Self.doomScale(context))
        case .matrix: return SIMD2(1, 1.25)
        case .snapOfDisintegration: return SIMD2(1.2, 1.2)
        case .tRexAttack: return SIMD2(repeating: 1 + 0.5 * 0.15)
        default: return SIMD2(1, 1)
        }
    }

    private static func doomScale(_ context: EffectContext) -> Float {
        2 * max(1, context.screenHeight / context.actorSize.y)
    }

    /// The uniforms of the effect, with the default settings of Burn-My-Windows and a fresh random seed.
    /// The names and kinds are fixed per effect: they define the layout of the parameter buffer.
    public func parameters(_ c: inout EffectContext) -> [EffectParameter] {
        switch self {
        case .aperturePanels:
            let panelSize: Float = 88
            let cols = max(1, (c.windowSize.x / panelSize).rounded())
            let rows = max(1, (c.windowSize.y / panelSize).rounded())
            // The cake is an Easter egg of the original: it shows up in 5% of the animations.
            let showCake = c.random() < 0.05
            return [
                .vec4("uFrame", c.padding, c.padding, c.windowSize.x, c.windowSize.y),
                .vec2("uCell", c.windowSize.x / cols, c.windowSize.y / rows),
                .float("uWaveShape", 4), .float("uVerticalAxis", 0), .float("uBorderStyle", 4),
                .rgba("uBorderColor", 0, 0, 0, 0.4), .float("uBlackVoid", 0),
                .float("uShowCake", showCake ? 1 : 0), .vec2("uCakePos", c.randomPair()),
            ]
        case .apparition:
            return [
                .vec2("uSeed", c.randomPair()), .float("uShake", 3), .float("uTwirl", 5),
                .float("uSuction", 0.75), .float("uRandomness", 0.5),
            ]
        case .auraGlow:
            return [
                .float("uSpeed", 2.5), .bool("uRandomColor", false), .float("uStartHue", 0),
                .float("uSaturation", 0.75), .float("uBlur", 15), .vec2("uSeed", c.randomPair()),
                .float("uEdgeSize", 0.75), .float("uEdgeHardness", 0.25),
            ]
        case .brokenGlass:
            return [
                .vec2("uSeed", c.randomPair()), .vec2("uEpicenter", 0.5, 0.5), .float("uShardScale", 1),
                .float("uBlowForce", 0.5), .float("uGravity", -1),
            ]
        case .doom:
            return [
                .float("uActorScale", Self.doomScale(c)), .float("uHorizontalScale", 10),
                .float("uVerticalScale", 10), .float("uPixelSize", 10),
            ]
        case .energizeA:
            return [.rgb("uColor", 255, 200, 50), .float("uScale", 1)]
        case .energizeB:
            return [.rgb("uColor", 160, 180, 255), .float("uScale", 1)]
        case .fire:
            return [
                .bool("u3DNoise", false), .float("uScale", 1), .float("uMovementSpeed", 0.5),
                .rgba("uGradient1", 76, 51, 25, 0), .rgba("uGradient2", 180, 55, 30, 0.7),
                .rgba("uGradient3", 255, 76, 38, 0.9), .rgba("uGradient4", 255, 166, 25, 1),
                .rgba("uGradient5", 255, 255, 255, 1), .bool("uRandomColor", false),
                .float("uSeed", c.random()), .bool("uClosingBottomToTop", false),
                .bool("uOpeningBottomToTop", false),
            ]
        case .focus:
            return [.float("uBlurAmount", 50), .float("uBlurQuality", 3)]
        case .glide:
            return [.float("uScale", 0.95), .float("uSquish", 0.15), .float("uTilt", -0.3), .float("uShift", -0.05)]
        case .glitch:
            return [
                .rgba("uColor", 100, 160, 255, 1), .float("uSeed", c.random()), .float("uScale", 1),
                .float("uStrength", 2), .float("uSpeed", 2),
            ]
        case .hexagon:
            return [
                .bool("uAdditiveBlending", true), .vec2("uSeed", c.randomPair()), .float("uScale", 3),
                .float("uLineWidth", 2), .rgba("uGlowColor", 20, 80, 255, 0.5),
                .rgba("uLineColor", 200, 255, 255, 0.5),
            ]
        case .incinerate:
            return [
                .vec2("uSeed", c.randomPair()), .rgb("uColor", 255, 180, 127), .float("uScale", 1),
                .float("uTurbulence", 0.3), .vec2("uStartPos", c.pointer),
            ]
        case .materialize:
            return [
                .vec4("uColor", c.accentColor.x, c.accentColor.y, c.accentColor.z, 0.85),
                .float("uStartScale", 0.6), .float("uSteps", 4),
            ]
        case .matrix:
            return [
                .rgb("uTrailColor", 25, 255, 89), .rgb("uTipColor", 255, 255, 255), .float("uLetterSize", 20),
                .float("uRandomness", 1), .float("uOverShoot", 0.25),
            ]
        case .morph:
            return [
                .vec4("uFrameRect", c.padding, c.padding, c.windowSize.x, c.windowSize.y),
                .vec2("uSeed", c.randomPair()), .float("uStyle", 0), .float("uStrength", 1),
            ]
        case .mushroom:
            return [
                .float("uScaleStyle", 1), .float("uSparkCount", 4), .rgba("uSparkColor", 255, 255, 255, 1),
                .float("uSparkRotation", 0.3), .rgba("uRaysColor", 255, 255, 255, 1), .float("uRingCount", 3),
                .float("uRingRotation", 1.33), .float("uStarCount", 5),
                .rgba("uStarColor0", 233, 249, 1, 1), .rgba("uStarColor1", 233, 249, 1, 1),
                .rgba("uStarColor2", 91, 255, 1, 1), .rgba("uStarColor3", 91, 255, 1, 1),
                .rgba("uStarColor4", 0, 240, 236, 1), .rgba("uStarColor5", 0, 240, 236, 1),
                .vec2("uSeed", c.randomPair()),
            ]
        case .paintBrush:
            return [.float("uBrushSize", 3)]
        case .pixelate:
            return [.float("uNoise", 40), .float("uPixelSize", 10)]
        case .pixelWheel:
            return [.float("uPixelSize", 10), .float("uSpokeCount", 12)]
        case .pixelWipe:
            return [.float("uPixelSize", 10), .vec2("uStartPos", c.pointer)]
        case .portal:
            return [
                .vec2("uSeed", c.randomPair()), .rgb("uColor", 121, 233, 24), .float("uRotationSpeed", 0.3),
                .float("uWhirling", 1), .float("uDetails", 15),
            ]
        case .rgbWarp:
            return [.float("uBrightness", 1), .float("uSpeedR", 1), .float("uSpeedG", 0.9), .float("uSpeedB", 0.8)]
        case .snapOfDisintegration:
            return [.rgba("uDustColor", 50, 40, 35, 1), .vec2("uSeed", c.randomPair()), .float("uDustScale", 3)]
        case .teamRocket:
            return [
                .float("uAnimationSplit", 0.5), .float("uHorizontalSparklePosition", 0),
                .float("uVerticalSparklePosition", 0.5), .bool("uWindowRotation", true),
                .float("uSparkleRot", 0.33), .float("uSparkleSize", 0.75), .vec2("uSeed", c.randomPair()),
            ]
        case .tRexAttack:
            return [
                .rgba("uFlashColor", 170, 0, 0, 1), .vec2("uSeed", c.randomPair()), .float("uClawSize", 1),
                .float("uNumClaws", 5), .float("uWarpIntensity", 0.15),
            ]
        case .tvEffect:
            return [.rgba("uColor", 255, 255, 255, 1)]
        case .tvGlitch:
            return [
                .rgba("uColor", 100, 160, 255, 1), .float("uSeed", c.random()), .float("uScale", 1),
                .float("uStrength", 2), .float("uSpeed", 2),
            ]
        case .wisps:
            return [
                .vec2("uSeed", c.randomPair()), .float("uScale", 1), .rgb("uColor1", 255, 100, 200),
                .rgb("uColor2", 100, 100, 255), .rgb("uColor3", 100, 200, 255),
            ]
        case .wormhole:
            let actor = c.actorSize
            return [
                .vec2("uCenter", actor / 2), .vec2("uAxes", max(8, c.windowSize.x / 2 * 1.35 + 80),
                                                    max(8, c.windowSize.y / 2 * 1.35 + 80)),
                .vec2("uFrameHalf", c.windowSize / 2), .float("uVoidSize", 0.65),
                .float("uTunnelDepth", 1), .float("uBounce", 0.5),
            ]
        }
    }
}

/// What the user picked in the menu: no effect, a random one on every close, or a specific one.
public enum CloseEffectChoice: Equatable, Sendable {
    case off
    case random
    case effect(CloseEffect)

    public init(rawValue: String?) {
        switch rawValue {
        case "off": self = .off
        case "random": self = .random
        case let id?: self = CloseEffect(rawValue: id).map(CloseEffectChoice.effect) ?? .effect(.fire)
        case nil: self = .effect(.fire)
        }
    }

    public var rawValue: String {
        switch self {
        case .off: return "off"
        case .random: return "random"
        case .effect(let effect): return effect.rawValue
        }
    }

    /// The effect to play for one close, or nil when effects are off.
    public func resolve<G: RandomNumberGenerator>(using generator: inout G) -> CloseEffect? {
        switch self {
        case .off: return nil
        case .random: return CloseEffect.allCases.randomElement(using: &generator)
        case .effect(let effect): return effect
        }
    }
}
