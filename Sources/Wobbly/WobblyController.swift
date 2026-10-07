// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
@preconcurrency import ApplicationServices
import WobblyCore

@MainActor
private final class DragSession {
    enum Phase {
        /// The mouse is holding the window.
        case dragging
        /// Released (or effect in progress): the jelly settles at `origin`.
        case settling
        /// Real window being moved back into place; waiting for the app to apply it.
        case restoring(deadline: CFTimeInterval)
        /// The real window is visible again: fading out the overlay's shadow, then removing the overlay.
        case closing(ticksLeft: Int)
        /// Can't animate (full screen, no AX…): just swallow the rest of the gesture.
        case aborted
    }

    let window: WindowInfo
    var phase = Phase.dragging
    var mouseDown = true
    var axResolved = false
    var axWindow: AXUIElement?
    var grabLocal: CGPoint
    var cursor: CGPoint
    /// Top-left corner of the rigid frame (where the window would be without deformation).
    var origin: CGPoint
    var deformer: WindowDeformer?
    var hideCountdown: Int?
    var hidden = false
    /// The overlay draws the shadow: only while the real window, with its native one, is parked.
    var overlayShadow = false
    /// Title bar height if the drag started on it (nil if it started with the shortcut).
    var titleBarHeight: CGFloat?
    /// Mouse-less effects (maximize, resize): they create their deformer once the capture arrives.
    var makeEffect: ((CGSize) -> WindowDeformer)?
    var tiles: (x: Int, y: Int)?
    /// Shadow of the capture on screen: the native one, which depends on whether the window was active.
    var shadow: ShadowInsets?

    init(window: WindowInfo, cursor: CGPoint) {
        self.window = window
        self.cursor = cursor
        origin = window.frame.origin
        grabLocal = CGPoint(x: cursor.x - origin.x, y: cursor.y - origin.y)
    }

    var model: WobblyModel? { makeEffect == nil ? deformer as? WobblyModel : nil }

    var isAborted: Bool {
        if case .aborted = phase { return true }
        return false
    }
}

/// The trick: when a window is grabbed it is captured with ScreenCaptureKit, drawn deformed in an overlay,
/// and the real window is parked off-screen via Accessibility. Once settled, it moves to its final place.
@MainActor
final class WobblyController: NSObject {
    /// Tags the clicks we replay ourselves so the tap lets them through.
    private static let replayMarker: Int64 = 0x574F_4242
    /// Window edge strip macOS uses for resizing: clicks there are never hijacked.
    private static let resizeBorder: CGFloat = 5

    /// Title bar click held back until we know whether it's a drag or a plain click.
    private struct PendingClick {
        let window: WindowInfo
        let point: CGPoint
        let titleBarHeight: CGFloat
        let downEvent: CGEvent
    }

    /// Window under a click we let through, in case it turns out to be a resize.
    private struct ResizeWatch {
        let window: WindowInfo
        let point: CGPoint
    }

    private let settings: Settings
    private let renderer: MeshRenderer
    private let capture = WindowCapture()
    private let mover = CoalescingMover()
    private let windowObserver = WindowObserver()
    private var overlays: [OverlayWindow] = []
    private var session: DragSession?
    private var pendingClick: PendingClick?
    private var resizeWatch: ResizeWatch?
    private var displayLink: CADisplayLink?
    /// Polls the real window while it is being parked or put back (see `watchRealWindow`).
    private var watcher: DispatchSourceTimer?
    private var lastTick: CFTimeInterval = 0
    private var precapture: (windowID: CGWindowID, startedAt: CFTimeInterval, task: Task<CapturedFrame?, Never>)?
    private var pendingZoom: (element: AXUIElement, pid: pid_t)?
    private var zoomTimer: Timer?
    private var maximizedWindows: Set<CGWindowID> = []

    init?(settings: Settings) {
        guard let renderer = MeshRenderer() else { return nil }
        self.settings = settings
        self.renderer = renderer
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        windowObserver.onResize = { [weak self] element, pid in self?.windowResized(element, pid: pid) }
        windowObserver.onWindowCreated = { [weak self] in self?.refreshCaptureContent() }
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(
                self, selector: #selector(refreshCaptureContent), name: name, object: nil)
        }
    }

    func warmUp() {
        Task { await capture.warmUp() }
        windowObserver.start()
    }

    /// Keeps the capture's window list current so a drag never has to wait for it. Skipped mid-gesture:
    /// raising the grabbed window activates its app, and the refresh would compete with that capture.
    @objc private func refreshCaptureContent() {
        guard session == nil, pendingClick == nil else { return }
        Task { await capture.refreshContent() }
    }

    /// Returns true if the event should be swallowed.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayMarker { return false }
        switch type {
        case .leftMouseDown:
            let windows = WindowList()
            let consumed = mouseDown(event, windows: windows)
            resizeWatch = consumed ? nil : watchForResize(at: event.location, windows: windows)
            return consumed
        case .leftMouseDragged:
            return mouseDragged(to: event.location)
        case .leftMouseUp:
            let consumed = mouseUp(event)
            if !consumed { checkForResize(endingAt: event.location) }
            return consumed
        case .flagsChanged:
            flagsChanged(event.flags)
            return false
        default:
            return false
        }
    }

    /// Ends any running animation and leaves the real window where it belongs.
    func cancelAll() {
        pendingClick = nil
        resizeWatch = nil
        if let session { finishImmediately(session) }
    }

    // MARK: - Mouse

    private func mouseDown(_ event: CGEvent, windows: WindowList) -> Bool {
        guard settings.enabled else { return false }
        let point = event.location
        let usesModifier = settings.modifier.matches(event.flags)
        let plainClick = event.flags.intersection(DragModifier.relevantFlags).isEmpty
        guard usesModifier || (settings.titleBarDrag && plainClick) else { return false }

        if let current = session {
            let frame = CGRect(origin: current.origin, size: current.window.frame.size)
            // Grabbing the window again while it is still wobbling: keep using the same mesh.
            if case .settling = current.phase, let model = current.model {
                let inTitleBar = point.y - frame.minY <= (current.titleBarHeight ?? 0)
                if frame.contains(point) && (usesModifier || inTitleBar) {
                    current.phase = .dragging
                    current.mouseDown = true
                    current.cursor = point
                    current.grabLocal = CGPoint(x: point.x - current.origin.x, y: point.y - current.origin.y)
                    model.grab(at: SIMD2(point))
                    return true
                }
            }
            // The real window is parked: if the click lands where it appears, put it back now so it gets the click.
            if frame.contains(point) { finishImmediately(current) }
        }

        guard let info = WindowLocator.window(at: point, in: windows) else { return false }
        if usesModifier {
            beginSession(info, at: point, titleBarHeight: nil)
            return true
        }

        // Without the shortcut: only the draggable area of the title bar, away from the resize edges.
        // The click is held back until we see whether the mouse moves; if it doesn't, it is replayed untouched.
        let local = CGPoint(x: point.x - info.frame.minX, y: point.y - info.frame.minY)
        guard local.y >= Self.resizeBorder, local.y <= 120,
              local.x >= Self.resizeBorder, info.frame.width - local.x >= Self.resizeBorder,
              let height = AXBridge.titleBarHeight(info, at: point),
              let downEvent = event.copy() else { return false }
        pendingClick = PendingClick(window: info, point: point, titleBarHeight: height, downEvent: downEvent)
        prefetch(info)
        return true
    }

    private func mouseDragged(to point: CGPoint) -> Bool {
        if let pending = pendingClick {
            guard hypot(point.x - pending.point.x, point.y - pending.point.y) >= 4 else { return true }
            pendingClick = nil
            beginSession(pending.window, at: pending.point, titleBarHeight: pending.titleBarHeight)
        }

        guard let session, session.mouseDown else { return false }
        session.cursor = point
        guard !session.isAborted else { return true }

        session.origin = CGPoint(x: point.x - session.grabLocal.x, y: point.y - session.grabLocal.y)
        if let model = session.model {
            model.moveGrab(to: SIMD2(point), origin: SIMD2(session.origin))
        } else if let axWindow = session.axWindow {
            // No capture yet: move the real window rigidly.
            mover.move(axWindow, to: session.origin)
        }
        return true
    }

    private func mouseUp(_ event: CGEvent) -> Bool {
        if let pending = pendingClick {
            pendingClick = nil
            replayClick(down: pending.downEvent, up: event)
            return true
        }

        guard let session, session.mouseDown else { return false }
        let point = event.location
        session.mouseDown = false
        if session.isAborted {
            self.session = nil
            return true
        }

        session.cursor = point
        session.origin = finalOrigin(for: session, cursor: point)
        session.phase = .settling
        if let model = session.model {
            model.release(origin: SIMD2(session.origin))
        } else if let axWindow = session.axWindow {
            mover.move(axWindow, to: session.origin)
            self.session = nil
        }
        // If AX hasn't answered yet, `axResolved` will place the window when it does.
        return true
    }

    /// Replays mouse down and up in order; the original `clickState` preserves double clicks.
    private func replayClick(down: CGEvent, up: CGEvent) {
        guard let up = up.copy() else { return }
        for event in [down, up] {
            event.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
            event.post(tap: .cgSessionEventTap)
        }
    }

    private func flagsChanged(_ flags: CGEventFlags) {
        guard settings.enabled, session == nil, settings.modifier.matches(flags),
              let cursor = CGEvent(source: nil)?.location,
              let info = WindowLocator.window(at: cursor) else { return }
        // Capture as soon as the modifier is pressed so the texture is ready by the time the user clicks.
        prefetch(info)
    }

    private func prefetch(_ info: WindowInfo) {
        if let precapture, precapture.windowID == info.id, CACurrentMediaTime() - precapture.startedAt < 1 { return }
        let task = Task { try? await capture.capture(info) }
        precapture = (info.id, CACurrentMediaTime(), task)
    }

    private func beginSession(_ info: WindowInfo, at point: CGPoint, titleBarHeight: CGFloat?) {
        if let previous = self.session { finishImmediately(previous, wait: false) }
        let session = DragSession(window: info, cursor: point)
        session.titleBarHeight = titleBarHeight
        self.session = session
        resolveAXWindow(for: session, hitPoint: point)

        guard let precapture, precapture.windowID == info.id, CACurrentMediaTime() - precapture.startedAt < 3 else {
            startCapture(for: session)
            return
        }
        let task = precapture.task
        Task {
            if let frame = await task.value, frame.pointSize == info.frame.size {
                attach(frame, to: session)
            } else {
                startCapture(for: session)
            }
        }
    }

    private func finalOrigin(for session: DragSession, cursor: CGPoint) -> CGPoint {
        var origin = CGPoint(x: (cursor.x - session.grabLocal.x).rounded(), y: (cursor.y - session.grabLocal.y).rounded())
        // macOS won't let the title bar end up under the menu bar; mirror that to avoid a jump at the end.
        if let screen = NSScreen.containing(cgPoint: cursor) {
            origin.y = max(origin.y, screen.cgFrame.minY + screen.menuBarHeight)
        }
        return origin
    }

    // MARK: - Maximize and resize effects

    private func watchForResize(at point: CGPoint, windows: WindowList) -> ResizeWatch? {
        guard settings.enabled, settings.resizeEffect, session == nil,
              let info = WindowLocator.window(near: point, margin: 8, in: windows) else { return nil }
        return ResizeWatch(window: info, point: point)
    }

    private func checkForResize(endingAt point: CGPoint) {
        guard let watch = resizeWatch else { return }
        resizeWatch = nil
        // The app may apply the final size a moment after the mouse is released.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated { self?.playResizeBounce(watch, endPoint: point) }
        }
    }

    private func playResizeBounce(_ watch: ResizeWatch, endPoint: CGPoint) {
        let old = watch.window.frame
        guard settings.resizeEffect, session == nil, let new = WindowLocator.frame(of: watch.window.id),
              abs(new.width - old.width) > 1 || abs(new.height - old.height) > 1,
              let edges = ResizeEdges.between(
                (Float(old.minX), Float(old.minY), Float(old.maxX), Float(old.maxY)),
                (Float(new.minX), Float(new.minY), Float(new.maxX), Float(new.maxY))) else { return }

        let info = WindowInfo(id: watch.window.id, pid: watch.window.pid, frame: new)
        let pickup = SIMD2<Float>(Float(watch.point.x - old.minX), Float(watch.point.y - old.minY))
        let travel = SIMD2<Float>(Float(endPoint.x - watch.point.x), Float(endPoint.y - watch.point.y))
        let physics = settings.physics
        AXBridge.queue(for: info.pid).async { [weak self] in
            guard let axWindow = AXBridge.findWindow(info, hitPoint: endPoint) else { return }
            Task { @MainActor in
                // GNOME uses 20×20 tiles for this effect.
                self?.startEffect(info, axWindow: axWindow, tiles: (20, 20)) { size in
                    ResizeBounce(size: SIMD2(Float(size.width), Float(size.height)), origin: SIMD2(info.frame.origin),
                                 edges: edges, pickup: pickup, pointerTravel: travel, settings: physics)
                }
            }
        }
    }

    /// Called by the AX observer when a window of the active app changes size. With no mouse button
    /// pressed it's a programmatic change (zoom, Fill, Rectangle…); wait for the animation to finish.
    private func windowResized(_ element: AXUIElement, pid: pid_t) {
        guard settings.enabled, settings.maximizeEffect, NSEvent.pressedMouseButtons == 0 else { return }
        pendingZoom = (element, pid)
        zoomTimer?.invalidate()
        zoomTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkZoom() }
        }
    }

    private func checkZoom() {
        guard let (element, pid) = pendingZoom else { return }
        pendingZoom = nil
        AXBridge.queue(for: pid).async { [weak self] in
            guard let frame = AXBridge.frame(of: element) else { return }
            Task { @MainActor in self?.playZoomEffect(element, pid: pid, frame: frame) }
        }
    }

    private func playZoomEffect(_ element: AXUIElement, pid: pid_t, frame: CGRect) {
        guard settings.maximizeEffect, session == nil,
              let info = WindowLocator.window(pid: pid, frame: frame),
              let screen = NSScreen.containing(cgPoint: CGPoint(x: frame.midX, y: frame.midY)) else { return }

        let visible = screen.cgVisibleFrame
        let tolerance: CGFloat = 16
        let maximized = abs(frame.minX - visible.minX) <= tolerance && abs(frame.minY - visible.minY) <= tolerance
            && abs(frame.maxX - visible.maxX) <= tolerance && abs(frame.maxY - visible.maxY) <= tolerance
        let wasMaximized = maximizedWindows.contains(info.id)
        guard maximized != wasMaximized else { return }

        let physics = settings.physics
        let origin = SIMD2<Float>(info.frame.origin)
        if maximized {
            maximizedWindows.insert(info.id)
            // GNOME forces 10×10 tiles when maximizing.
            startEffect(info, axWindow: element, tiles: (10, 10)) { size in
                let model = WobblyModel(size: SIMD2(Float(size.width), Float(size.height)), origin: origin, settings: physics)
                model.maximize()
                return model
            }
        } else {
            maximizedWindows.remove(info.id)
            startEffect(info, axWindow: element, tiles: nil) { size in
                let model = WobblyModel(size: SIMD2(Float(size.width), Float(size.height)), origin: origin, settings: physics)
                model.unmaximize()
                return model
            }
        }
    }

    private func startEffect(_ info: WindowInfo, axWindow: AXUIElement, tiles: (x: Int, y: Int)?,
                             make: @escaping (CGSize) -> WindowDeformer) {
        guard session == nil else { return }
        let session = DragSession(window: info, cursor: CGPoint(x: info.frame.midX, y: info.frame.midY))
        session.mouseDown = false
        session.phase = .settling
        session.axWindow = axWindow
        session.axResolved = true
        session.makeEffect = make
        session.tiles = tiles
        self.session = session
        startCapture(for: session)
    }

    // MARK: - Capture and AX

    private func resolveAXWindow(for session: DragSession, hitPoint: CGPoint) {
        let info = session.window
        AXBridge.queue(for: info.pid).async { [weak self] in
            let axWindow = AXBridge.findWindow(info, hitPoint: hitPoint)
            let fullScreen = axWindow.map(AXBridge.isFullScreen) ?? false
            if let axWindow, !fullScreen { AXBridge.raise(axWindow, pid: info.pid) }
            Task { @MainActor in
                self?.axResolved(session, axWindow: fullScreen ? nil : axWindow)
            }
        }
    }

    private func axResolved(_ session: DragSession, axWindow: AXUIElement?) {
        guard self.session === session else { return }
        session.axResolved = true
        session.axWindow = axWindow
        guard let axWindow else {
            abort(session)
            return
        }
        if session.deformer == nil {
            mover.move(axWindow, to: session.origin)
            if !session.mouseDown { self.session = nil }
        }
        if self.session === session { recaptureAfterRaise(session) }
    }

    /// The first capture is taken before raising the window: a background window has the inactive look there
    /// (smaller shadow, grey title bar) but comes back active at the end, which shows as a jump. Capture again
    /// once the activation has landed and swap it in if the shadow changed.
    private func recaptureAfterRaise(_ session: DragSession) {
        Task {
            for delay in [0.15, 0.25] {
                try? await Task.sleep(for: .seconds(delay))
                guard self.session === session, !session.isAborted,
                      let frame = try? await capture.capture(session.window), self.session === session else { return }
                if session.deformer == nil {
                    attach(frame, to: session)
                    return
                }
                switch session.phase {
                case .dragging, .settling: break
                default: return
                }
                guard frame.pointSize == session.window.frame.size,
                      session.shadow.map(frame.shadow.differs(from:)) ?? false else { continue }
                if renderer.setFrame(frame) { session.shadow = frame.shadow }
                return
            }
        }
    }

    private func startCapture(for session: DragSession) {
        Task {
            do {
                let frame = try await capture.capture(session.window)
                attach(frame, to: session)
            } catch {
                // No Screen Recording permission (or the window can't be captured): fall back to a rigid drag.
                NSLog("Wobbly: capture failed: \(error)")
                if self.session === session, session.makeEffect != nil { self.session = nil }
            }
        }
    }

    private func attach(_ frame: CapturedFrame, to session: DragSession) {
        guard self.session === session, session.deformer == nil else { return }
        if session.makeEffect == nil {
            guard case .dragging = session.phase else { return }
        }
        guard renderer.setFrame(frame) else { return }
        precapture = nil
        session.shadow = frame.shadow

        let deformer: WindowDeformer
        if let make = session.makeEffect {
            deformer = make(frame.pointSize)
        } else {
            let model = WobblyModel(
                size: SIMD2(Float(frame.pointSize.width), Float(frame.pointSize.height)),
                origin: SIMD2(session.origin),
                settings: settings.physics)
            model.grab(at: SIMD2(session.cursor))
            deformer = model
        }
        session.deformer = deformer
        session.hideCountdown = 2

        // The real window stays underneath with its native shadow until it is parked.
        renderer.shadowOpacity = 0
        updateScene(session, deformer)
        if overlays.isEmpty {
            overlays = NSScreen.screens.map { OverlayWindow(screen: $0, renderer: renderer) }
        }
        overlays.forEach { $0.render() }
        overlays.forEach { $0.show() }
        startDisplayLink(near: session.cursor)
    }

    private func updateScene(_ session: DragSession, _ deformer: WindowDeformer) {
        let tiles = session.tiles ?? (settings.tilesX, settings.tilesY)
        renderer.update(from: deformer, tilesX: tiles.x, tilesY: tiles.y)
    }

    // MARK: - Animation

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTick == 0 ? 1.0 / 120.0 : now - lastTick
        lastTick = now

        guard let session, let deformer = session.deformer else {
            stopDisplayLink()
            return
        }

        switch session.phase {
        case .dragging, .settling:
            deformer.step(Float(dt))
            if case .settling = session.phase, deformer.isSettled {
                deformer.snapToRest()
                beginRestore(session)
            } else {
                hideRealWindowIfDue(session)
            }
        case .restoring(let deadline):
            // Normally the watcher started in `beginRestore` gets here first, as soon as the window is back.
            if now > deadline { realWindowRestored(session) }
        case .closing(let ticksLeft):
            if ticksLeft == 1 {
                renderer.clearScene()
            } else if ticksLeft <= 0 {
                tearDown()
                return
            }
            session.phase = .closing(ticksLeft: ticksLeft - 1)
        case .aborted:
            break
        }

        renderer.shadowOpacity = session.overlayShadow && settings.shadow ? 1 : 0
        if renderer.hasScene { updateScene(session, deformer) }
        overlays.forEach { $0.render() }
    }

    private func hideRealWindowIfDue(_ session: DragSession) {
        guard let countdown = session.hideCountdown, session.axResolved, let axWindow = session.axWindow else { return }
        guard countdown <= 0 else {
            session.hideCountdown = countdown - 1
            return
        }
        // The overlay has been on screen for a couple of frames: now it's safe to park the real window.
        session.hideCountdown = nil
        session.hidden = true
        let parking = parkingPoint()
        let before = WindowLocator.frame(of: session.window.id)
        AXBridge.queue(for: axWindow).async { AXBridge.setPosition(axWindow, parking) }
        watchRealWindow(session, timeout: 0.25, until: { Self.offset($0, from: before) > 2 }) { [weak self] in
            self?.setOverlayShadow(true, session)
        }
    }

    private func beginRestore(_ session: DragSession) {
        session.hideCountdown = nil
        session.phase = .restoring(deadline: CACurrentMediaTime() + 0.5)
        let target = session.origin
        if let axWindow = session.axWindow {
            AXBridge.queue(for: axWindow).async { AXBridge.setPosition(axWindow, target) }
        }
        // Never parked: the native shadow never left, nothing to hand over.
        guard session.hidden else {
            realWindowRestored(session)
            return
        }
        let rest = CGRect(origin: target, size: session.window.frame.size)
        watchRealWindow(session, timeout: 0.5, until: { Self.offset($0, from: rest) <= 8 }) { [weak self] in
            self?.realWindowRestored(session)
        }
    }

    private func realWindowRestored(_ session: DragSession) {
        guard self.session === session, case .restoring = session.phase else { return }
        setOverlayShadow(false, session)
        session.phase = .closing(ticksLeft: 2)
    }

    /// The real window moves 1-2 frames after the AX call returns (whenever its app commits), so neither waiting
    /// for the call nor checking once per frame catches the frame WindowServer shows the move in: one shadow
    /// would be missing, or both drawn, for a frame or two. Polling every millisecond while it happens, and
    /// switching shadows right away, gets the overlay's change into that same frame.
    private func watchRealWindow(_ session: DragSession, timeout: CFTimeInterval, until arrived: @escaping (CGRect?) -> Bool,
                                 then action: @escaping () -> Void) {
        watcher?.cancel()
        let start = CACurrentMediaTime()
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(1), leeway: .nanoseconds(0))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.session === session else {
                    timer.cancel()
                    return
                }
                guard arrived(WindowLocator.frame(of: session.window.id)) || CACurrentMediaTime() - start > timeout else { return }
                timer.cancel()
                self.watcher = nil
                action()
            }
        }
        watcher = timer
        timer.resume()
    }

    private static func offset(_ frame: CGRect?, from reference: CGRect?) -> CGFloat {
        guard let frame, let reference else { return 0 }
        return max(abs(frame.minX - reference.minX), abs(frame.minY - reference.minY))
    }

    /// Redraws right away instead of at the next tick: WindowServer is about to composite the frame the real
    /// window moved in, and the overlay's change has to make it into that same frame.
    private func setOverlayShadow(_ on: Bool, _ session: DragSession) {
        session.overlayShadow = on
        renderer.shadowOpacity = on && settings.shadow ? 1 : 0
        overlays.forEach { $0.render() }
    }

    /// Bottom-right corner of all screens: the window is left with 1 pt visible,
    /// the same trick AeroSpace uses to hide windows without private APIs.
    private func parkingPoint() -> CGPoint {
        let union = NSScreen.screens.reduce(CGRect.null) { $0.union($1.cgFrame) }
        return CGPoint(x: union.maxX - 1, y: union.maxY - 1)
    }

    private func abort(_ session: DragSession) {
        if session.hidden, let axWindow = session.axWindow {
            let target = session.origin
            AXBridge.queue(for: axWindow).async { AXBridge.setPosition(axWindow, target) }
        }
        session.phase = .aborted
        session.deformer = nil
        clearOverlays()
        if !session.mouseDown { self.session = nil }
    }

    /// `wait` blocks until the window is back: needed when a click is about to land on it or the app is quitting.
    /// Grabbing another window doesn't need it, and waiting there would freeze the event tap.
    private func finishImmediately(_ session: DragSession, wait: Bool = true) {
        if let axWindow = session.axWindow, session.deformer != nil {
            let target = session.origin
            let queue = AXBridge.queue(for: axWindow)
            if wait {
                queue.sync { AXBridge.setPosition(axWindow, target) }
            } else {
                queue.async { AXBridge.setPosition(axWindow, target) }
            }
        }
        tearDown()
    }

    private func tearDown() {
        clearOverlays()
        session = nil
    }

    private func clearOverlays() {
        watcher?.cancel()
        watcher = nil
        renderer.clearScene()
        overlays.forEach {
            $0.render()
            $0.hide()
        }
        stopDisplayLink()
    }

    private func startDisplayLink(near point: CGPoint) {
        guard displayLink == nil else { return }
        let screen = NSScreen.containing(cgPoint: point) ?? NSScreen.screens.first
        guard let link = screen?.displayLink(target: self, selector: #selector(tick(_:))) else { return }
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTick = 0
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func screensChanged() {
        cancelAll()
        overlays.forEach { $0.close() }
        overlays = []
    }
}

private extension SIMD2 where Scalar == Float {
    init(_ point: CGPoint) {
        self.init(Float(point.x), Float(point.y))
    }
}
