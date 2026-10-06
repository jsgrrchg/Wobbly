// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import simd

/// Something that deforms a window: the wobbly model or the resize bounce.
///
/// Global coordinates in points with the Y axis pointing down (the same as CGEvent, AX and CGWindowList).
/// `origin` is the top-left corner of the rigid frame: where the real window ends up when done.
public protocol WindowDeformer: AnyObject {
    var size: SIMD2<Float> { get }
    var origin: SIMD2<Float> { get }
    var isSettled: Bool { get }
    func step(_ dt: Float)
    func snapToRest()
    /// Displacement from the rigid frame at (u, v) ∈ [0, 1]².
    func displacement(u: Float, v: Float) -> SIMD2<Float>
}

extension WindowDeformer {
    public func point(u: Float, v: Float) -> SIMD2<Float> {
        origin + SIMD2(u * size.x, v * size.y) + displacement(u: min(max(u, 0), 1), v: min(max(v, 0), 1))
    }

    /// Fills a grid of (tilesX + 1) × (tilesY + 1) vertices `(x, y, u, v)`.
    /// `margin` (in points) extends the grid past the edges; outside the window the edge displacement
    /// is used, so the shadow follows the deformation.
    public func fillVertices(tilesX: Int, tilesY: Int, margin: Float = 0, into out: inout [SIMD4<Float>]) {
        out.removeAll(keepingCapacity: true)
        let mu = margin / size.x
        let mv = margin / size.y
        for j in 0...tilesY {
            let v = -mv + (1 + 2 * mv) * Float(j) / Float(tilesY)
            for i in 0...tilesX {
                let u = -mu + (1 + 2 * mu) * Float(i) / Float(tilesX)
                let p = point(u: u, v: v)
                out.append(SIMD4(p.x, p.y, u, v))
            }
        }
    }

    public var maxDisplacement: Float {
        var result: Float = 0
        for j in 0...8 {
            for i in 0...8 {
                result = max(result, simd_length(displacement(u: Float(i) / 8, v: Float(j) / 8)))
            }
        }
        return result
    }
}
