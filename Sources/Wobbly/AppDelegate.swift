// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices
import WobblyCore

enum Permissions {
    static func accessibilityGranted(prompt: Bool) -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
    }

    static var screenCaptureGranted: Bool { CGPreflightScreenCaptureAccess() }

    static func openPrivacySettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private var controller: WobblyController?
    private var tap: EventTap?
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private weak var presetItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = WobblyController(settings: settings)
        setUpStatusItem()
        installSignalHandlers()

        guard controller != nil else {
            NSLog("Wobbly: Metal unavailable")
            return
        }
        if !Permissions.screenCaptureGranted { CGRequestScreenCaptureAccess() }
        if !startTap(prompt: true) {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.startTap(prompt: false) else { return }
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.cancelAll()
        tap?.stop()
    }

    @discardableResult
    private func startTap(prompt: Bool) -> Bool {
        guard Permissions.accessibilityGranted(prompt: prompt), let controller else { return false }
        let tap = EventTap { type, event in controller.handle(type, event) }
        tap.onDisabled = { controller.cancelAll() }
        guard tap.start() else { return false }
        self.tap = tap
        controller.warmUp()
        return true
    }

    /// If we get killed with SIGTERM/SIGINT mid-animation, the real window must not stay parked.
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: - Menu

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "water.waves", accessibilityDescription: "Wobbly")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let enabled = NSMenuItem(title: "Wobbly Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.state = settings.enabled ? .on : .off
        menu.addItem(enabled)
        menu.addItem(.separator())

        let titleBar = NSMenuItem(title: "Drag from Title Bar", action: #selector(toggleTitleBarDrag), keyEquivalent: "")
        titleBar.state = settings.titleBarDrag ? .on : .off
        menu.addItem(titleBar)

        let modifierMenu = NSMenu()
        for modifier in DragModifier.allCases {
            let entry = NSMenuItem(title: modifier.title, action: #selector(selectModifier(_:)), keyEquivalent: "")
            entry.representedObject = modifier.rawValue
            entry.state = settings.modifier == modifier ? .on : .off
            entry.target = self
            modifierMenu.addItem(entry)
        }
        let modifierItem = NSMenuItem(title: "Shortcut (Anywhere): \(settings.modifier.title)", action: nil, keyEquivalent: "")
        modifierItem.submenu = modifierMenu
        menu.addItem(modifierItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem.sectionHeader(title: "Compiz Effect"))

        let presetMenu = NSMenu()
        for preset in WobblePreset.allCases {
            let entry = NSMenuItem(title: preset.title, action: #selector(selectPreset(_:)), keyEquivalent: "")
            entry.representedObject = preset.rawValue
            entry.state = settings.preset == preset ? .on : .off
            entry.target = self
            presetMenu.addItem(entry)
        }
        let presetItem = NSMenuItem(title: "Preset: \(settings.preset.title)", action: nil, keyEquivalent: "")
        presetItem.submenu = presetMenu
        menu.addItem(presetItem)
        self.presetItem = presetItem

        let physics = settings.physics
        addSlider(to: menu, "Friction", Double(physics.friction), Settings.frictionRange, decimals: 1) { [unowned self] value in
            updatePhysics { $0.friction = Float(value) }
        }
        addSlider(to: menu, "Spring", Double(physics.spring), Settings.springRange, decimals: 1) { [unowned self] value in
            updatePhysics { $0.spring = Float(value) }
        }
        addSlider(to: menu, "Speedup", Double(physics.speedup), Settings.speedupRange, decimals: 1) { [unowned self] value in
            updatePhysics { $0.speedup = Float(value) }
        }
        addSlider(to: menu, "Mass", Double(physics.mass), Settings.massRange, decimals: 0) { [unowned self] value in
            updatePhysics { $0.mass = Float(value) }
        }
        addSlider(to: menu, "Tiles X", Double(settings.tilesX), Settings.tilesRange, decimals: 0) { [unowned self] value in
            settings.tilesX = Int(value)
        }
        addSlider(to: menu, "Tiles Y", Double(settings.tilesY), Settings.tilesRange, decimals: 0) { [unowned self] value in
            settings.tilesY = Int(value)
        }

        let maximize = NSMenuItem(title: "Effect on Maximize", action: #selector(toggleMaximizeEffect), keyEquivalent: "")
        maximize.state = settings.maximizeEffect ? .on : .off
        menu.addItem(maximize)
        let resize = NSMenuItem(title: "Effect on Resize", action: #selector(toggleResizeEffect), keyEquivalent: "")
        resize.state = settings.resizeEffect ? .on : .off
        menu.addItem(resize)
        let shadow = NSMenuItem(title: "Shadow", action: #selector(toggleShadow), keyEquivalent: "")
        shadow.state = settings.shadow ? .on : .off
        menu.addItem(shadow)
        menu.addItem(NSMenuItem(title: "Reset to Defaults", action: #selector(resetToDefaults), keyEquivalent: ""))
        menu.addItem(.separator())

        if controller == nil {
            menu.addItem(NSMenuItem(title: "Metal Unavailable", action: nil, keyEquivalent: ""))
        }
        let accessibility = Permissions.accessibilityGranted(prompt: false)
        menu.addItem(NSMenuItem(
            title: accessibility ? "Accessibility: Granted" : "Grant Accessibility…",
            action: accessibility ? nil : #selector(openAccessibility), keyEquivalent: ""))
        let screenCapture = Permissions.screenCaptureGranted
        menu.addItem(NSMenuItem(
            title: screenCapture ? "Screen Recording: Granted" : "Grant Screen Recording…",
            action: screenCapture ? nil : #selector(openScreenCapture), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Wobbly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action != nil && item.action != #selector(NSApplication.terminate(_:)) && item.target == nil {
            item.target = self
        }
    }

    @objc private func toggleEnabled() {
        settings.enabled.toggle()
        if !settings.enabled { controller?.cancelAll() }
    }

    private func addSlider(to menu: NSMenu, _ title: String, _ value: Double, _ range: ClosedRange<Double>,
                           decimals: Int, onChange: @escaping (Double) -> Void) {
        let item = NSMenuItem()
        item.view = SliderMenuView(title: title, value: value, range: range, decimals: decimals, onChange: onChange)
        menu.addItem(item)
    }

    /// Moving a physics slider switches the preset to "Custom", like the GNOME extension does.
    private func updatePhysics(_ change: (inout WobblySettings) -> Void) {
        var physics = settings.physics
        change(&physics)
        settings.physics = physics
        settings.preset = .custom
        presetItem?.title = "Preset: \(WobblePreset.custom.title)"
    }

    @objc private func toggleMaximizeEffect() {
        settings.maximizeEffect.toggle()
    }

    @objc private func toggleResizeEffect() {
        settings.resizeEffect.toggle()
    }

    @objc private func resetToDefaults() {
        settings.resetToDefaults()
    }

    @objc private func toggleTitleBarDrag() {
        settings.titleBarDrag.toggle()
    }

    @objc private func toggleShadow() {
        settings.shadow.toggle()
    }

    @objc private func selectModifier(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let modifier = DragModifier(rawValue: raw) {
            settings.modifier = modifier
        }
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let preset = WobblePreset(rawValue: raw) {
            settings.preset = preset
        }
    }

    @objc private func openAccessibility() {
        Permissions.openPrivacySettings("Privacy_Accessibility")
    }

    @objc private func openScreenCapture() {
        CGRequestScreenCaptureAccess()
        Permissions.openPrivacySettings("Privacy_ScreenCapture")
    }
}
