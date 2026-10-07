// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import os

struct WindowInfo {
    let id: CGWindowID
    let pid: pid_t
    /// Frame in global CoreGraphics coordinates (origin at the top left of the main screen).
    let frame: CGRect
}

/// One CGWindowList query (several ms with many windows) shared by every lookup made for the same event.
final class WindowList {
    fileprivate lazy var entries = WindowLocator.onScreenWindows()
}

enum WindowLocator {
    private static let ownPID = ProcessInfo.processInfo.processIdentifier

    /// Frontmost normal window (layer 0) under `point`. If the first thing there is a menu,
    /// the Dock or another special layer, returns nil so the click isn't hijacked.
    static func window(at point: CGPoint, in list: WindowList = WindowList()) -> WindowInfo? {
        window(near: point, margin: 0, in: list)
    }

    /// Like `window(at:)` but accepting clicks up to `margin` points outside the frame,
    /// where macOS lets you grab the edges to resize.
    static func window(near point: CGPoint, margin: CGFloat, in list: WindowList = WindowList()) -> WindowInfo? {
        for entry in list.entries {
            guard let info = parse(entry), info.pid != ownPID, info.frame.insetBy(dx: -margin, dy: -margin).contains(point) else { continue }
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha < 0.01 { continue }
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            if layer != 0 {
                if isPassThroughOverlay(entry, frame: info.frame, layer: layer, point: point) { continue }
                logBlocker(entry, frame: info.frame, layer: layer)
                return nil
            }
            guard info.frame.width >= 80, info.frame.height >= 40 else { return nil }
            return info
        }
        return nil
    }

    /// Screen recorders that put transparent layers on top (region border, clicks, camera…).
    /// Matched by bundle ID because the process name is localized ("Screenshot", "Captura de Pantalla"…).
    private static let captureOverlayBundleIDs: Set<String> = [
        "com.apple.screencaptureui", "pl.maketheweb.cleanshotx", "com.wulkano.kap", "com.loom.desktop",
        "com.obsproject.obs-studio", "so.screen.studio", "net.telestream.screenflow10",
    ]
    /// Processes without a bundle (the `screencapture` command-line tool).
    private static let captureOverlayOwners: Set<String> = ["screencapture"]
    /// Full-screen layers that do receive clicks and must not be treated as pass-through.
    private static let blockingOwners: Set<String> = ["loginwindow", "ScreenSaverEngine"]
    private static let dockLevel = Int(CGWindowLevelForKey(.dockWindow))

    /// Special layers are usually menus, panels or the Dock, and they block the effect. But the ones covering
    /// the whole screen (recorders, dimmers, "show clicks" tools…) almost always let the mouse through.
    private static func isPassThroughOverlay(_ entry: [String: Any], frame: CGRect, layer: Int, point: CGPoint) -> Bool {
        let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
        if blockingOwners.contains(owner) { return false }
        // While recording, WindowServer draws the cursor (and indicators) as small windows of its own,
        // right under the pointer. The menu bar is also its own, but much larger.
        if owner == "Window Server" { return frame.width <= 128 && frame.height <= 128 }
        if owner == "Dock" {
            // When the Dock is visible it puts a transparent full-screen layer at the Dock level; it only
            // blocks over the bar itself. Mission Control and Launchpad use other levels and do block.
            return layer == dockLevel && screenCoverage(of: frame) >= 0.9 && !DockBar.contains(point)
        }
        if captureOverlayOwners.contains(owner) { return true }
        if let pid = entry[kCGWindowOwnerPID as String] as? Int,
           let bundleID = NSRunningApplication(processIdentifier: pid_t(pid))?.bundleIdentifier,
           captureOverlayBundleIDs.contains(bundleID) { return true }
        return screenCoverage(of: frame) >= 0.9
    }

    private static func screenCoverage(of frame: CGRect) -> CGFloat {
        NSScreen.screens.map { screen in
            let screenFrame = screen.cgFrame
            let overlap = screenFrame.intersection(frame)
            return overlap.isNull ? 0 : (overlap.width * overlap.height) / (screenFrame.width * screenFrame.height)
        }.max() ?? 0
    }

    private static let log = Logger(subsystem: "io.github.jsgrrchg.Wobbly", category: "hit-test")

    /// Menus and the menu bar block on purpose and would show up on every click: only large layers and
    /// small windows from other apps (like the cursor WindowServer draws while recording) are logged.
    private static func logBlocker(_ entry: [String: Any], frame: CGRect, layer: Int) {
        let small = frame.width <= 128 && frame.height <= 128
        guard screenCoverage(of: frame) >= 0.25 || small else { return }
        let owner = entry[kCGWindowOwnerName as String] as? String ?? "?"
        let name = entry[kCGWindowName as String] as? String ?? "-"
        log.notice("Layer blocking the effect: \(owner, privacy: .public) “\(name, privacy: .public)” layer \(layer) frame \(NSStringFromRect(frame), privacy: .public)")
    }

    /// Normal window of `pid` whose frame matches `frame` (to map an AX element to its CGWindowID).
    static func window(pid: pid_t, frame: CGRect) -> WindowInfo? {
        for entry in onScreenWindows() {
            guard let info = parse(entry), info.pid == pid,
                  (entry[kCGWindowLayer as String] as? Int ?? 0) == 0,
                  abs(info.frame.minX - frame.minX) <= 2, abs(info.frame.minY - frame.minY) <= 2,
                  abs(info.frame.width - frame.width) <= 2, abs(info.frame.height - frame.height) <= 2 else { continue }
            return info
        }
        return nil
    }

    fileprivate static func onScreenWindows() -> [[String: Any]] {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    }

    static func frame(of id: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let entry = list.first else { return nil }
        return parse(entry)?.frame
    }

    private static func parse(_ entry: [String: Any]) -> WindowInfo? {
        guard let number = entry[kCGWindowNumber as String] as? Int,
              let pid = entry[kCGWindowOwnerPID as String] as? Int,
              let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
        return WindowInfo(id: CGWindowID(number), pid: pid_t(pid), frame: frame)
    }
}

/// Area of the Dock bar, queried from the Dock itself via Accessibility (cached for half a second
/// because it is checked from the event tap).
private enum DockBar {
    private static var cached: (frame: CGRect?, at: CFTimeInterval)?

    static func contains(_ point: CGPoint) -> Bool {
        let now = CACurrentMediaTime()
        if cached == nil || now - cached!.at > 0.5 {
            cached = (currentFrame(), now)
        }
        // If we don't know where the bar is, err on the side of blocking.
        return cached?.frame?.contains(point) ?? true
    }

    private static func currentFrame() -> CGRect? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.05)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return nil }
        let lists = children.filter { child in
            var role: CFTypeRef?
            return AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role) == .success
                && role as? String == kAXListRole as String
        }
        let frames = lists.compactMap(AXBridge.frame(of:))
        return frames.isEmpty ? nil : frames.reduce(CGRect.null) { $0.union($1) }
    }
}

extension NSScreen {
    /// Screen frame in CoreGraphics coordinates (Y pointing down).
    var cgFrame: CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? frame.height
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// Usable area (excluding menu bar and Dock) in CoreGraphics coordinates.
    var cgVisibleFrame: CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? frame.height
        return CGRect(x: visibleFrame.minX, y: primaryHeight - visibleFrame.maxY, width: visibleFrame.width, height: visibleFrame.height)
    }

    /// Height reserved at the top by the menu bar (notch included).
    var menuBarHeight: CGFloat { frame.maxY - visibleFrame.maxY }

    static func containing(cgPoint point: CGPoint) -> NSScreen? {
        screens.first { $0.cgFrame.contains(point) }
    }
}
