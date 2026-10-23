// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import QuartzCore
import WobblyEffects

/// Decides when a window is being closed, and plays the close effect as it goes away.
///
/// An app closes its windows on its own, so nothing can be intercepted: by the time the window is gone
/// there is nothing left to capture. Instead the window is captured beforehand, when a close is likely, and watched:
///
/// - A click in the top-left corner of a window (where the close button is) captures it; if the window starts
///   to close within a moment of the click, the effect plays.
/// - Holding ⌘ captures the focused window, refreshing the capture while ⌘ is held, so that ⌘W (or ⌘Q) finds
///   a fresh one. Keystrokes are never read: this relies only on the modifier flags the event tap already sees.
///
/// A window that is closing is recognized by what macOS does with it: it fades the window out (the opacity in the
/// window list drops) or removes it at once. A window that is minimized, hidden or on another Space leaves the screen
/// without fading and still exists, so it triggers nothing. Neither do ⌘W on a tab nor a close that the app refuses
/// (an unsaved-changes sheet).
@MainActor
final class CloseEffectTrigger {
    private struct Watch {
        let window: WindowInfo
        /// Latest known frame of the window, in case it moved after being captured.
        var lastFrame: CGRect
        var capture: CapturedFrame?
        var capturedAt: CFTimeInterval = 0
        var capturing = false
        /// The window has been seen fully opaque on screen, so a drop in opacity is a fade-out and not a fade-in.
        var sawOpaque = false
        /// A capture started with the click that may still be running when the window goes away.
        var pending: Task<CapturedFrame?, Never>?
        /// Time after which the window is no longer expected to close (infinity while ⌘ is held).
        var deadline: CFTimeInterval
    }

    /// Area of a window, from its top-left corner, where a click may be on a close button.
    private static let closeButtonArea = CGSize(width: 110, height: 52)
    /// How long after a click on the close button the window may take to go away.
    private static let clickGrace: CFTimeInterval = 1.5
    /// How long after ⌘ is released the window may take to go away.
    private static let commandGrace: CFTimeInterval = 0.8
    /// A capture of the focused window older than this is replaced while ⌘ is held.
    private static let refreshAge: CFTimeInterval = 0.6
    /// A capture that arrives later than this after the window went away is not worth playing.
    private static let latestStart: CFTimeInterval = 0.4
    /// Opacity below which a window is considered to be fading out.
    private static let fadeThreshold = 0.97

    private let settings: Settings
    private let capture: WindowCapture
    private let player: CloseEffectPlayer
    /// True while a wobble animation owns the overlays and the windows.
    private let isBusy: () -> Bool
    private var watches: [CGWindowID: Watch] = [:]
    private var clickCandidate: (window: WindowInfo, task: Task<CapturedFrame?, Never>)?
    private var commandHeld = false
    private var timer: DispatchSourceTimer?

    init(settings: Settings, capture: WindowCapture, player: CloseEffectPlayer, isBusy: @escaping () -> Bool) {
        self.settings = settings
        self.capture = capture
        self.player = player
        self.isBusy = isBusy
    }

    private var enabled: Bool { settings.enabled && settings.closeEffect != .off }

    // MARK: - Events

    /// A mouse click that was passed on to the app.
    func mouseDown(at point: CGPoint, windows: WindowList) {
        guard enabled, !isBusy(), let info = WindowLocator.window(at: point, in: windows) else { return }
        let local = CGPoint(x: point.x - info.frame.minX, y: point.y - info.frame.minY)
        guard local.x >= 0, local.y >= 0, local.x <= Self.closeButtonArea.width, local.y <= Self.closeButtonArea.height else { return }
        // The capture takes longer than the app takes to close the window, so it starts with the click.
        let task = Task { try? await capture.capture(info) }
        clickCandidate = (info, task)
    }

    func mouseUp() {
        guard let candidate = clickCandidate else { return }
        clickCandidate = nil
        guard enabled else { return }
        let window = candidate.window
        start(window, deadline: CACurrentMediaTime() + Self.clickGrace)
        watches[window.id]?.pending = candidate.task
        Task {
            guard let frame = await candidate.task.value else { return }
            self.watches[window.id]?.capture = frame
            self.watches[window.id]?.capturedAt = CACurrentMediaTime()
        }
    }

    func flagsChanged(_ flags: CGEventFlags) {
        let command = flags.intersection(DragModifier.relevantFlags) == .maskCommand
        if command, !commandHeld {
            commandHeld = true
            captureFocusedWindow()
        } else if commandHeld, !flags.contains(.maskCommand) {
            releaseCommand()
        }
    }

    func cancelAll() {
        clickCandidate = nil
        commandHeld = false
        watches.removeAll()
        stopTimer()
        player.cancelAll()
    }

    // MARK: - Capturing

    private func captureFocusedWindow() {
        guard enabled, !isBusy(), let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let pid = app.processIdentifier
        // Accessibility calls go through the app's own queue: a slow app must not freeze the event tap.
        AXBridge.queue(for: pid).async { [weak self] in
            let focused = AXBridge.focusedWindow(pid: pid)
            Task { @MainActor in
                guard let self, self.commandHeld, let focused,
                      focused.frame.width >= 80, focused.frame.height >= 40 else { return }
                self.start(focused, deadline: .infinity)
            }
        }
    }

    private func releaseCommand() {
        commandHeld = false
        let deadline = CACurrentMediaTime() + Self.commandGrace
        for id in watches.keys where watches[id]?.deadline == .infinity {
            watches[id]?.deadline = deadline
        }
    }

    /// Starts watching `window`, or extends the watch it already has.
    private func start(_ window: WindowInfo, deadline: CFTimeInterval) {
        if let existing = watches[window.id] {
            watches[window.id]?.deadline = max(existing.deadline, deadline)
        } else {
            watches[window.id] = Watch(window: window, lastFrame: window.frame, deadline: deadline)
        }
        player.setArmed(true)
        startTimer()
        if deadline == .infinity { refreshCapture(of: window.id) }
    }

    private func refreshCapture(of id: CGWindowID) {
        guard let watch = watches[id], !watch.capturing, CACurrentMediaTime() - watch.capturedAt > Self.refreshAge else { return }
        watches[id]?.capturing = true
        let info = WindowInfo(id: id, pid: watch.window.pid, frame: watch.lastFrame)
        Task {
            let frame = try? await capture.capture(info)
            self.watches[id]?.capturing = false
            if let frame {
                self.watches[id]?.capture = frame
                self.watches[id]?.capturedAt = CACurrentMediaTime()
            }
        }
    }

    // MARK: - Watching

    /// Polled every few milliseconds, like the handover of the wobbly overlay: the effect has to start in the
    /// same frame in which the window disappears.
    private func startTimer() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(4), leeway: .nanoseconds(0))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.poll() }
        }
        self.timer = timer
        timer.resume()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
        player.setArmed(false)
    }

    private func poll() {
        let now = CACurrentMediaTime()
        // If a ⌘ release was missed (the event tap was off for a moment), don't watch forever.
        if commandHeld, !NSEvent.modifierFlags.contains(.command) { releaseCommand() }

        for (id, watch) in watches {
            guard let current = WindowLocator.snapshot(of: id) else {
                // Off screen. If it was on screen a moment ago it was removed without a fade, or it was minimized,
                // hidden or sent to another Space: only a window that no longer exists is a close.
                watches[id] = nil
                if watch.sawOpaque, !WindowLocator.exists(id) {
                    closed(watch, fading: false)
                    rearmWhileCommandHeld()
                }
                continue
            }

            if current.alpha >= 0.99 {
                watches[id]?.sawOpaque = true
            } else if watch.sawOpaque, current.alpha < Self.fadeThreshold {
                // macOS has started to fade the window out. The capture still matches it.
                watches[id] = nil
                closed(watch, fading: true)
                rearmWhileCommandHeld()
                continue
            }

            if current.alpha >= Self.fadeThreshold { watches[id]?.lastFrame = current.frame }
            if now > watch.deadline {
                watches[id] = nil
            } else if commandHeld, watch.deadline == .infinity {
                refreshCapture(of: id)
            }
        }
        if watches.isEmpty { stopTimer() }
    }

    /// With ⌘ still held, the next window to take focus (when closing several in a row) is captured too.
    private func rearmWhileCommandHeld() {
        guard commandHeld else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated {
                if let self, self.commandHeld { self.captureFocusedWindow() }
            }
        }
    }

    /// The window is closing: plays the effect on its last capture.
    /// `fading` is true while macOS' own fade-out is still running underneath the effect.
    private func closed(_ watch: Watch, fading: Bool) {
        guard enabled, !isBusy(), let effect = player.effect(for: settings.closeEffect),
              // Hiding the app fades its windows out too, but they come back.
              !(NSRunningApplication(processIdentifier: watch.window.pid)?.isHidden ?? false) else { return }
        let windowFrame = watch.lastFrame
        let pointer = CGEvent(source: nil)?.location ?? CGPoint(x: windowFrame.minX + 24, y: windowFrame.minY + 22)
        let speed = settings.closeDuration

        func play(_ frame: CapturedFrame) {
            // A capture of another size means the window was resized after it: it would be drawn distorted.
            guard frame.pointSize == windowFrame.size else { return }
            player.play(frame, windowFrame: windowFrame, effect: effect, pointer: pointer, durationScale: speed, nativeFade: fading)
        }

        if let frame = watch.capture {
            play(frame)
        } else if let pending = watch.pending {
            // The capture started with the click is still running: use it when it arrives, if it isn't too late.
            let limit = CACurrentMediaTime() + Self.latestStart
            Task {
                guard let frame = await pending.value, CACurrentMediaTime() < limit else { return }
                play(frame)
            }
        }
    }
}
