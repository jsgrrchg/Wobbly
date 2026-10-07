// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
@preconcurrency import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Access to other apps' windows through the public Accessibility API.
/// Every call is IPC with the owning app, so they run on `queue` and never on the main thread.
enum AXBridge {
    static let queue = DispatchQueue(label: "wobbly.ax", qos: .userInteractive)

    static func findWindow(_ info: WindowInfo, hitPoint: CGPoint) -> AXUIElement? {
        let app = AXUIElementCreateApplication(info.pid)
        AXUIElementSetMessagingTimeout(app, 0.25)

        var value: CFTypeRef?
        let windows = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success
            ? value as? [AXUIElement] ?? [] : []
        // Exact match: identical frames are common (maximized or tiled windows of the same app on other Spaces).
        if let exact = windows.first(where: { windowID(of: $0) == info.id }) { return exact }

        // Fallback: what the app says is under the cursor can only be on the current Space.
        if let hit = hitTest(info.pid, at: hitPoint, timeout: 0.25),
           let window = role(of: hit) == kAXWindowRole as String ? hit : element(hit, kAXWindowAttribute) {
            return window
        }

        // Last resort: frame match, but only if unambiguous. Guessing would park the wrong window.
        let candidates = windows.filter { frame(of: $0).map { matches($0, info.frame) } ?? false }
        return candidates.count == 1 ? candidates[0] : nil
    }

    /// CGWindowID behind an AX window (private, but stable for years and used by yabai, AeroSpace, AltTab…).
    static func windowID(of window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(window, &id) == .success ? id : nil
    }

    private static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }

    private static let draggableRoles: Set<String> = [
        kAXWindowRole as String, kAXToolbarRole as String, kAXGroupRole as String, kAXStaticTextRole as String,
    ]

    /// If `point` falls on a draggable area of the title bar (not a button, tab or field), returns the
    /// height of that bar. It is inferred from the close button, which macOS centers vertically in it;
    /// windows without a close button (games, borderless windows) are skipped.
    /// Called from the event tap, so it uses a short timeout.
    static func titleBarHeight(_ info: WindowInfo, at point: CGPoint) -> CGFloat? {
        guard let hit = hitTest(info.pid, at: point, timeout: 0.1),
              let role = role(of: hit), draggableRoles.contains(role) else { return nil }

        let window = role == kAXWindowRole as String ? hit : element(hit, kAXWindowAttribute)
        guard let window, let close = element(window, kAXCloseButtonAttribute), let closeFrame = frame(of: close),
              info.frame.contains(CGPoint(x: closeFrame.midX, y: closeFrame.midY)) else { return nil }

        let height = 2 * (closeFrame.midY - info.frame.minY)
        guard height >= 20, height <= 120, point.y - info.frame.minY <= height else { return nil }
        return height
    }

    /// Asks the owning app rather than the system-wide element, so transparent layers from other apps
    /// (screen recorders, for example) don't get in the way. `WindowLocator` has already checked that
    /// the window is frontmost.
    private static func hitTest(_ pid: pid_t, at point: CGPoint, timeout: Float) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success else { return nil }
        return hit
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let origin = point(window, kAXPositionAttribute), let size = size(window) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func setPosition(_ window: AXUIElement, _ point: CGPoint) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    static func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    static func raise(_ window: AXUIElement, pid: pid_t) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func size(_ element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }
}

/// Moves a window along with the mouse, keeping only the latest requested position
/// so dozens of AX calls don't pile up if the app is slow to respond.
final class CoalescingMover {
    private let lock = NSLock()
    private var pending: (AXUIElement, CGPoint)?
    private var scheduled = false

    func move(_ window: AXUIElement, to point: CGPoint) {
        lock.lock()
        pending = (window, point)
        let needsSchedule = !scheduled
        scheduled = true
        lock.unlock()
        guard needsSchedule else { return }

        AXBridge.queue.async { [self] in
            lock.lock()
            let job = pending
            pending = nil
            scheduled = false
            lock.unlock()
            if let (window, point) = job { AXBridge.setPosition(window, point) }
        }
    }
}
