// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// Copyright (C) 2020 Mauro Pepe <https://github.com/hermes83/compiz-windows-effect>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Bounce after a resize ends, ported from src/effects/resize.js of the GNOME extension
// "Compiz windows effect" by Mauro Pepe (GPL-3.0-or-later). In GNOME the window also deforms
// during the resize; here we can only do the final bounce because the app redraws live.
import Foundation
import simd

public struct ResizeEdges: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let left = ResizeEdges(rawValue: 1)
    public static let right = ResizeEdges(rawValue: 2)
    public static let top = ResizeEdges(rawValue: 4)
    public static let bottom = ResizeEdges(rawValue: 8)

    /// Edges that changed between two frames (Y pointing down); nil if it isn't an edge or corner resize.
    public static func between(_ old: (minX: Float, minY: Float, maxX: Float, maxY: Float),
                               _ new: (minX: Float, minY: Float, maxX: Float, maxY: Float)) -> ResizeEdges? {
        let tolerance: Float = 1
        var edges: ResizeEdges = []
        let left = abs(new.minX - old.minX) > tolerance
        let right = abs(new.maxX - old.maxX) > tolerance
        let top = abs(new.minY - old.minY) > tolerance
        let bottom = abs(new.maxY - old.maxY) > tolerance
        // If both sides of an axis moved it's a move or a zoom, not a dragged edge.
        if left && right || top && bottom { return nil }
        if left { edges.insert(.left) }
        if right { edges.insert(.right) }
        if top { edges.insert(.top) }
        if bottom { edges.insert(.bottom) }
        return edges.isEmpty ? nil : edges
    }
}

public final class ResizeBounce: WindowDeformer {
    private static let duration: Float = 1
    private static let endDivider: Float = 4
    private static let cornerDivider: Float = 6

    public let size: SIMD2<Float>
    public let origin: SIMD2<Float>
    private let edges: ResizeEdges
    private let pickup: SIMD2<Float>
    private let stop: SIMD2<Float>
    private let endMultiplier: Float
    private var elapsed: Float = 0
    private var delta = SIMD2<Float>.zero

    /// - Parameters:
    ///   - pickup: point where the edge was grabbed, relative to the window's corner.
    ///   - pointerTravel: total cursor travel during the resize.
    public init(size: SIMD2<Float>, origin: SIMD2<Float>, edges: ResizeEdges, pickup: SIMD2<Float>,
                pointerTravel: SIMD2<Float>, settings: WobblySettings) {
        self.size = size
        self.origin = origin
        self.edges = edges
        self.pickup = pickup
        // In GNOME: delta += (previous - new) * spring * 0.2 on every event; on release, stop = delta * 1.5.
        stop = -pointerTravel * (settings.spring * 0.2) * 1.5
        endMultiplier = settings.friction * 10 + 10
    }

    public var isSettled: Bool { elapsed >= Self.duration }

    public func step(_ dt: Float) {
        elapsed = min(elapsed + max(dt, 0), Self.duration)
        let i = elapsed / Self.duration * endMultiplier
        delta = stop * (sin(i) / exp(i / Self.endDivider))
    }

    public func snapToRest() {
        elapsed = Self.duration
        delta = .zero
    }

    public func displacement(u: Float, v: Float) -> SIMD2<Float> {
        let w = size.x
        let h = size.y
        let x = u * w
        let y = v * h
        let dx = delta.x
        let dy = delta.y
        let c = Self.cornerDivider
        func sq(_ value: Float) -> Float { value * value }

        switch edges {
        case [.left]:
            return SIMD2(dx * (w - x) * sq(y - pickup.y) / (sq(h) * w), 0)
        case [.right]:
            return SIMD2(dx * x * sq(y - pickup.y) / (sq(h) * w), 0)
        case [.bottom]:
            return SIMD2(0, dy * y * sq(x - pickup.x) / (sq(w) * h))
        case [.top]:
            return SIMD2(0, dy * (h - y) * sq(x - pickup.x) / (sq(w) * h))
        case [.top, .left]:
            return SIMD2(dx / c * (w - x) * sq(y) / (sq(h) * w), dy / c * (h - y) * sq(x) / (sq(w) * h))
        case [.top, .right]:
            return SIMD2(dx / c * x * sq(y) / (sq(h) * w), dy / c * (h - y) * sq(w - x) / (sq(w) * h))
        case [.bottom, .right]:
            return SIMD2(dx / c * x * sq(h - y) / (sq(h) * w), dy / c * y * sq(w - x) / (sq(w) * h))
        case [.bottom, .left]:
            return SIMD2(dx / c * (w - x) * sq(y - h) / (sq(h) * w), dy / c * y * sq(x) / (sq(w) * h))
        default:
            return .zero
        }
    }
}
