// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

/// Headless rendering of the close effects: used by the tests and by the `wobbly-effects-preview` tool to
/// check the shaders and to write contact sheets, without opening any window.
///
/// The window image is drawn like a real macOS window (title bar, traffic lights, content, native-looking
/// shadow) and laid out like a ScreenCaptureKit capture: the window offset inside a buffer that also holds its shadow.
public final class EffectPreview {
    public static let windowSize = CGSize(width: 640, height: 420)
    /// Shadow room around the window in the capture (the app captures up to 100 pt).
    public static let shadowRoom: CGFloat = 60
    public static let frameProgress: [Float] = [0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1]

    public struct Frame {
        /// Premultiplied BGRA.
        public var pixels: [UInt8]
        public var width: Int
        public var height: Int

        /// Mean alpha (0...1) over `region`, in pixels of the frame.
        public func meanAlpha(in region: CGRect) -> Double {
            var sum = 0.0, count = 0.0
            for y in max(0, Int(region.minY))..<min(height, Int(region.maxY)) {
                for x in max(0, Int(region.minX))..<min(width, Int(region.maxX)) {
                    sum += Double(pixels[(y * width + x) * 4 + 3]) / 255
                    count += 1
                }
            }
            return count > 0 ? sum / count : 0
        }

        public func image() -> CGImage? {
            var copy = pixels
            return copy.withUnsafeMutableBytes { buffer in
                CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)?
                    .makeImage()
            }
        }
    }

    public let device: MTLDevice
    public let renderer: CloseEffectRenderer
    private let queue: MTLCommandQueue
    private let capture: MTLTexture
    private let captureSize: SIMD2<Float>

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw EffectError.compilation("no Metal device")
        }
        self.device = device
        self.queue = queue
        renderer = CloseEffectRenderer(device: device)
        (capture, captureSize) = try Self.makeCapture(device: device)
    }

    /// An effect scene on the sample window, with a fixed seed unless one is given.
    public func scene(for effect: CloseEffect, seed: UInt64 = 42) -> EffectScene {
        let room = Float(Self.shadowRoom)
        let windowFrame = CGRect(x: 300, y: 200, width: Self.windowSize.width, height: Self.windowSize.height)
        return EffectScene(
            effect: effect, texture: capture,
            uvScale: SIMD2(Float(Self.windowSize.width), Float(Self.windowSize.height)) / captureSize,
            uvOffset: SIMD2(room, room) / captureSize, windowFrame: windowFrame, padding: room,
            // The pointer is where the close button is: top left of the window.
            pointer: CGPoint(x: windowFrame.minX + 24, y: windowFrame.minY + 22), screenHeight: 900,
            accentColor: SIMD3(0.04, 0.52, 1), seed: seed)
    }

    /// The window's interior (without its edges), in pixels of a frame rendered for `scene`.
    public static func interior(of scene: EffectScene) -> CGRect {
        let size = scene.quadRect.size
        return CGRect(x: (size.width - windowSize.width) / 2 + 40, y: (size.height - windowSize.height) / 2 + 40,
                      width: windowSize.width - 80, height: windowSize.height - 80)
    }

    /// Renders one frame covering the effect's quad, over a transparent background.
    public func render(_ scene: EffectScene, progress: Float) throws -> Frame {
        var scene = scene
        scene.progress = progress
        let rect = scene.quadRect
        let width = Int(rect.width.rounded()), height = Int(rect.height.rounded())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: descriptor), let commandBuffer = queue.makeCommandBuffer() else {
            throw EffectError.compilation("out of GPU memory")
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            throw EffectError.compilation("no render encoder")
        }
        let drawn = renderer.encode(scene, into: encoder, screenRect: rect)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if !drawn { throw EffectError.compilation("\(scene.effect.title) can't be drawn") }
        if let error = commandBuffer.error { throw EffectError.compilation("\(scene.effect.title): \(error)") }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return Frame(pixels: pixels, width: width, height: height)
    }

    /// Frames of one effect laid out in a grid over a gradient (so transparency is visible), at a third of the size.
    public func contactSheet(for effect: CloseEffect, columns: Int = 4) throws -> CGImage? {
        let scene = scene(for: effect)
        let tile = CGSize(width: (scene.quadRect.width / 3).rounded(), height: (scene.quadRect.height / 3).rounded())
        let rows = (Self.frameProgress.count + columns - 1) / columns
        let size = CGSize(width: tile.width * CGFloat(columns), height: tile.height * CGFloat(rows))
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [CGColor(red: 0.10, green: 0.16, blue: 0.32, alpha: 1), CGColor(red: 0.15, green: 0.45, blue: 0.5, alpha: 1)]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])

        for (index, progress) in Self.frameProgress.enumerated() {
            guard let image = try render(scene, progress: progress).image() else { continue }
            context.draw(image, in: CGRect(
                x: CGFloat(index % columns) * tile.width, y: size.height - CGFloat(index / columns + 1) * tile.height,
                width: tile.width, height: tile.height))
        }
        return context.makeImage()
    }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw EffectError.resourceMissing(url.path)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw EffectError.resourceMissing(url.path) }
    }

    // MARK: - Sample window

    private static func makeCapture(device: MTLDevice) throws -> (MTLTexture, SIMD2<Float>) {
        let room = shadowRoom
        let width = Int(windowSize.width + 2 * room), height = Int(windowSize.height + 2 * room)
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info) else { return false }
            // Top-left origin, like the capture.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            drawWindow(in: context, room: room)
            return true
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard drawn, let texture = device.makeTexture(descriptor: descriptor) else {
            throw EffectError.compilation("can't create the sample window")
        }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels, bytesPerRow: bytesPerRow)
        return (texture, SIMD2(Float(width), Float(height)))
    }

    private static func drawWindow(in context: CGContext, room: CGFloat) {
        let frame = CGRect(x: room, y: room, width: windowSize.width, height: windowSize.height)
        let path = CGPath(roundedRect: frame, cornerWidth: 12, cornerHeight: 12, transform: nil)

        // Native-looking shadow: soft, shifted down.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -22), blur: 36, color: CGColor(gray: 0, alpha: 0.42))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.addPath(path)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(path)
        context.clip()

        context.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1))
        context.fill(frame)

        // Sidebar.
        context.setFillColor(CGColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1))
        context.fill(CGRect(x: frame.minX, y: frame.minY, width: 150, height: frame.height))

        // Title bar with traffic lights.
        let colors = [CGColor(red: 0.90, green: 0.90, blue: 0.91, alpha: 1), CGColor(red: 0.82, green: 0.82, blue: 0.84, alpha: 1)]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: frame.minY), end: CGPoint(x: 0, y: frame.minY + 46), options: [])
        for (index, color) in [(0.95, 0.38, 0.35), (0.98, 0.75, 0.2), (0.35, 0.78, 0.3)].enumerated() {
            context.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
            context.fillEllipse(in: CGRect(x: frame.minX + 16 + CGFloat(index) * 22, y: frame.minY + 17, width: 12, height: 12))
        }

        // Content: colored blocks and text lines, so every effect has something to show.
        let accents = [
            CGColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1), CGColor(red: 0.95, green: 0.45, blue: 0.25, alpha: 1),
            CGColor(red: 0.30, green: 0.75, blue: 0.45, alpha: 1), CGColor(red: 0.65, green: 0.35, blue: 0.85, alpha: 1),
        ]
        for (index, accent) in accents.enumerated() {
            context.setFillColor(accent)
            context.fill(CGRect(x: frame.minX + 175 + CGFloat(index) * 112, y: frame.minY + 70, width: 96, height: 96))
        }
        context.setFillColor(CGColor(gray: 0.25, alpha: 1))
        for line in 0..<9 {
            context.fill(CGRect(x: frame.minX + 175, y: frame.minY + 200 + CGFloat(line) * 20,
                                width: 430 - CGFloat((line * 53) % 160), height: 8))
        }
        context.setFillColor(CGColor(gray: 0.35, alpha: 1))
        for line in 0..<14 {
            context.fill(CGRect(x: frame.minX + 16, y: frame.minY + 70 + CGFloat(line) * 22, width: 100 - CGFloat((line * 37) % 40), height: 9))
        }
        context.restoreGState()
    }
}
