// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreMedia
import CoreVideo
import QuartzCore
import ScreenCaptureKit

/// Immutable and backed by an IOSurface: safe to pass between tasks.
struct CapturedFrame: @unchecked Sendable {
    let windowID: CGWindowID
    let pixelBuffer: CVPixelBuffer
    let pointSize: CGSize
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

    func capture(_ info: WindowInfo) async throws -> CapturedFrame {
        var window = content?.windows.first { $0.windowID == info.id }
        if window == nil {
            window = await refreshContent()?.windows.first { $0.windowID == info.id }
        }
        guard let window else { throw CaptureError.windowNotShareable }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = max(1, Int((info.frame.width * scale).rounded()))
        config.height = max(1, Int((info.frame.height * scale).rounded()))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.displayP3
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.captureResolution = .best

        let sample = try await SCScreenshotManager.captureSampleBuffer(contentFilter: filter, configuration: config)
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { throw CaptureError.emptySample }
        return CapturedFrame(windowID: info.id, pixelBuffer: pixelBuffer, pointSize: info.frame.size, capturedAt: CACurrentMediaTime())
    }
}
