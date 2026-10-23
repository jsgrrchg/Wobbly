// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import MetalKit

/// What an overlay draws: a scene in global coordinates, rendered once per screen it touches.
@MainActor
protocol OverlayContent: AnyObject {
    var device: MTLDevice { get }
    var hasScene: Bool { get }
    /// Bounding box of the scene, in global CG coordinates.
    var sceneBounds: CGRect { get }
    func draw(in view: MTKView, screenRect: CGRect)
}

/// Transparent, full-screen, click-through window where the "jelly" window is drawn.
@MainActor
final class OverlayWindow: NSObject, MTKViewDelegate {
    let screenRect: CGRect
    private let window: NSWindow
    private let view: MTKView
    private unowned let renderer: OverlayContent
    private var showingContent = false

    init(screen: NSScreen, renderer: OverlayContent) {
        self.renderer = renderer
        screenRect = screen.cgFrame

        view = MTKView(frame: NSRect(origin: .zero, size: screen.frame.size), device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.colorspace = WindowCapture.colorSpace
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.framebufferOnly = true
        view.layer?.isOpaque = false
        if let layer = view.layer as? CAMetalLayer {
            // Hand each frame to WindowServer as soon as it's drawn instead of at the next vsync, so a redraw made
            // mid-frame (when the real window moves) lands in the frame being composited. A third drawable keeps
            // that extra redraw from blocking on the next tick's.
            layer.displaySyncEnabled = false
            layer.maximumDrawableCount = 3
        }

        window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = view

        super.init()
        view.delegate = self
        window.setFrame(screen.frame, display: false)
    }

    var displayLinkWindow: NSWindow { window }

    func show() {
        window.orderFrontRegardless()
    }

    /// Puts the overlay in front with nothing drawn on it.
    func showBlank() {
        showingContent = true
        view.draw()
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
        showingContent = false
    }

    func close() {
        window.close()
    }

    /// Redraws if the scene touches this screen, or one last time to clear it if it just left.
    func render() {
        let touches = renderer.hasScene && renderer.sceneBounds.intersects(screenRect)
        guard touches || showingContent else { return }
        showingContent = touches
        view.draw()
    }

    func draw(in view: MTKView) {
        renderer.draw(in: view, screenRect: screenRect)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
