// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
@preconcurrency import ApplicationServices

/// Reports when a window of the active app changes size (zoom, Fill, window managers…).
/// Only the frontmost app is observed: it's the only one that can be maximized with a click or shortcut.
@MainActor
final class WindowObserver {
    var onResize: ((AXUIElement, pid_t) -> Void)?
    var onWindowCreated: (() -> Void)?

    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var activationToken: NSObjectProtocol?

    func start() {
        guard activationToken == nil else { return }
        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { self?.observe(pid) }
        }
        observe(NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    private func observe(_ pid: pid_t?) {
        guard let pid, pid != observedPID, pid != ProcessInfo.processInfo.processIdentifier else { return }
        stopObserving()

        var created: AXObserver?
        guard AXObserverCreate(pid, observerCallback, &created) == .success, let observer = created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, refcon)
        AXObserverAddNotification(observer, app, kAXWindowResizedNotification as CFString, refcon)

        // Besides the app-level notification, register each window too: not every app sends the former.
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
           let windows = value as? [AXUIElement] {
            for window in windows {
                AXObserverAddNotification(observer, window, kAXResizedNotification as CFString, refcon)
            }
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = observer
        observedPID = pid
    }

    private func stopObserving() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedPID = 0
    }

    fileprivate func handle(_ element: AXUIElement, notification: String) {
        if notification == kAXWindowCreatedNotification as String {
            if let observer {
                AXObserverAddNotification(observer, element, kAXResizedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
            }
            onWindowCreated?()
            return
        }
        onResize?(element, observedPID)
    }
}

private func observerCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let windowObserver = Unmanaged<WindowObserver>.fromOpaque(refcon).takeUnretainedValue()
    // The run loop source lives on the main thread.
    MainActor.assumeIsolated { windowObserver.handle(element, notification: notification as String) }
}
