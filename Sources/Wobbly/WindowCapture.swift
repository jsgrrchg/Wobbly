// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreMedia
import CoreVideo
import QuartzCore
import ScreenCaptureKit

/// How far a window's shadow reaches past each edge, in points.
struct ShadowInsets: Equatable {
    var left: CGFloat = 0, top: CGFloat = 0, right: CGFloat = 0, bottom: CGFloat = 0

    func differs(from other: ShadowInsets) -> Bool {
        max(abs(left - other.left), abs(top - other.top), abs(right - other.right), abs(bottom - other.bottom)) > 2
    }
}

/// Immutable and backed by an IOSurface: safe to pass between tasks.
struct CapturedFrame: @unchecked Sendable {
    let windowID: CGWindowID
    /// The window plus its native shadow around it.
    let pixelBuffer: CVPixelBuffer
    /// Size of the window itself, without the shadow.
    let pointSize: CGSize
    /// Where the window sits in `pixelBuffer`, in pixels.
    let windowRect: CGRect
    let shadow: ShadowInsets
    let capturedAt: CFTimeInterval
}

enum CaptureError: Error {
    case windowNotShareable
    case emptySample
}

/// Captures a single window with ScreenCaptureKit (`desktopIndependentWindow` filter),
/// so the overlay never captures itself or anything sitting on top of the window.
@MainActor
final class WindowCapture {
    static let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!

    private var content: SCShareableContent?
    private var refreshTask: Task<SCShareableContent?, Never>?

    /// Fetching the shareable content list takes tens of ms, so it is cached and refreshed ahead of time
    /// (at launch, on app activation, Space changes and new windows). It includes windows on every Space,
    /// so switching Spaces doesn't leave the cache without the windows the user is about to drag.
    @discardableResult
    func refreshContent() async -> SCShareableContent? {
        if let refreshTask { return await refreshTask.value }
        let task = Task<SCShareableContent?, Never> {
            try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        if let result { content = result }
        return result
    }

    /// The first capture in a process is much slower than the rest: take a tiny one at launch
    /// so the first drag doesn't pay for it.
    func warmUp() async {
        guard let window = await refreshContent()?.windows.first(where: {
            $0.isOnScreen && $0.windowLayer == 0 && $0.frame.width >= 1 && $0.frame.height >= 1
        }) else { return }
        let config = SCStreamConfiguration()
        config.width = 16
        config.height = 16
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        _ = try? await SCScreenshotManager.captureSampleBuffer(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
    }

    /// Room around the window for its shadow (an active window's reaches ~56 pt sideways and ~72 pt down).
    private static let shadowRoom: CGFloat = 100

    /// Captures the window with its native shadow, so the overlay's shadow is the real one and nothing
    /// changes when the real window takes over. Falls back to the bare window if it can't be located.
    func capture(_ info: WindowInfo) async throws -> CapturedFrame {
        var window = content?.windows.first { $0.windowID == info.id }
        if window == nil {
            window = await refreshContent()?.windows.first { $0.windowID == info.id }
        }
        guard let window else { throw CaptureError.windowNotShareable }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let windowPixels = CGSize(width: (info.frame.width * scale).rounded(), height: (info.frame.height * scale).rounded())
        let room = (Self.shadowRoom * scale).rounded()

        let sample = try await SCScreenshotManager.captureSampleBuffer(
            contentFilter: filter, configuration: configuration(width: windowPixels.width + 2 * room,
                                                                height: windowPixels.height + 2 * room, shadow: true))
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sample),
           let (windowRect, shadow) = Self.locateWindow(in: pixelBuffer, size: windowPixels, scale: scale) {
            return CapturedFrame(windowID: info.id, pixelBuffer: pixelBuffer, pointSize: info.frame.size,
                                 windowRect: windowRect, shadow: shadow, capturedAt: CACurrentMediaTime())
        }

        let bare = try await SCScreenshotManager.captureSampleBuffer(
            contentFilter: filter, configuration: configuration(width: windowPixels.width, height: windowPixels.height, shadow: false))
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(bare) else { throw CaptureError.emptySample }
        return CapturedFrame(windowID: info.id, pixelBuffer: pixelBuffer, pointSize: info.frame.size,
                             windowRect: CGRect(origin: .zero, size: windowPixels), shadow: ShadowInsets(),
                             capturedAt: CACurrentMediaTime())
    }

    private func configuration(width: CGFloat, height: CGFloat, shadow: Bool) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = max(1, Int(width))
        config.height = max(1, Int(height))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.displayP3
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = !shadow
        // Unscaled, window and shadow land 1:1 in the top-left corner of the buffer.
        config.scalesToFit = false
        config.captureResolution = .best
        return config
    }

    /// Finds the window inside a capture that includes its shadow: the opaque run across the middle row and
    /// column, which must match the window size. The shadow is the non-transparent part around it.
    /// Returns nil for windows that aren't opaque there (translucent terminals, HUDs…).
    private static func locateWindow(in buffer: CVPixelBuffer, size: CGSize, scale: CGFloat) -> (CGRect, ShadowInsets)? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        func alpha(_ x: Int, _ y: Int) -> UInt8 { base[y * bytesPerRow + x * 4 + 3] }

        // The shadow is ~15-40 pt at the top and ~20-60 pt at the sides, so these always cross the window.
        let row = min(height - 1, Int(size.height / 2 + 30 * scale))
        let column = min(width - 1, Int(size.width / 2 + 40 * scale))
        let xs = 0..<width, ys = 0..<height
        guard let left = xs.first(where: { alpha($0, row) >= 250 }), let right = xs.last(where: { alpha($0, row) >= 250 }),
              let top = ys.first(where: { alpha(column, $0) >= 250 }), let bottom = ys.last(where: { alpha(column, $0) >= 250 }),
              abs(CGFloat(right - left + 1) - size.width) <= 2, abs(CGFloat(bottom - top + 1) - size.height) <= 2 else { return nil }

        let shadowLeft = xs.first { alpha($0, row) > 0 } ?? left
        let shadowRight = xs.last { alpha($0, row) > 0 } ?? right
        let shadowTop = ys.first { alpha(column, $0) > 0 } ?? top
        let shadowBottom = ys.last { alpha(column, $0) > 0 } ?? bottom
        let shadow = ShadowInsets(left: CGFloat(left - shadowLeft) / scale, top: CGFloat(top - shadowTop) / scale,
                                  right: CGFloat(shadowRight - right) / scale, bottom: CGFloat(shadowBottom - bottom) / scale)
        return (CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1), shadow)
    }
}
