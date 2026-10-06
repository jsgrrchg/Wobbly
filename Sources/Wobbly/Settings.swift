// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import WobblyCore

enum DragModifier: String, CaseIterable {
    case controlCommand
    case optionCommand
    case controlOption
    case option

    static let relevantFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    var flags: CGEventFlags {
        switch self {
        case .controlCommand: return [.maskControl, .maskCommand]
        case .optionCommand: return [.maskAlternate, .maskCommand]
        case .controlOption: return [.maskControl, .maskAlternate]
        case .option: return [.maskAlternate]
        }
    }

    var title: String {
        switch self {
        case .controlCommand: return "⌃⌘ + Drag"
        case .optionCommand: return "⌥⌘ + Drag"
        case .controlOption: return "⌃⌥ + Drag"
        case .option: return "⌥ + Drag"
        }
    }

    func matches(_ flags: CGEventFlags) -> Bool {
        flags.intersection(Self.relevantFlags) == self.flags
    }
}

enum WobblePreset: String, CaseIterable {
    case subtle, realistic, exaggerated, extreme, custom

    var settings: WobblySettings? {
        switch self {
        case .subtle: return .subtle
        case .realistic: return .realistic
        case .exaggerated: return .exaggerated
        case .extreme: return .extreme
        case .custom: return nil
        }
    }

    var title: String {
        switch self {
        case .subtle: return "Subtle"
        case .realistic: return "Realistic"
        case .exaggerated: return "Exaggerated"
        case .extreme: return "Extreme"
        case .custom: return "Custom"
        }
    }
}

/// The same settings as the GNOME extension "Compiz windows effect", with the same ranges.
final class Settings {
    static let frictionRange: ClosedRange<Double> = 1...10
    static let springRange: ClosedRange<Double> = 1...10
    static let speedupRange: ClosedRange<Double> = 2...40
    static let massRange: ClosedRange<Double> = 20...80
    static let tilesRange: ClosedRange<Double> = 3...20

    private static let defaultTilesX = 16
    private static let defaultTilesY = 14

    private let defaults = UserDefaults.standard

    var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }

    /// Drag from the title bar without holding any shortcut.
    var titleBarDrag: Bool {
        get { defaults.object(forKey: "titleBarDrag") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "titleBarDrag") }
    }

    var modifier: DragModifier {
        get { defaults.string(forKey: "modifier").flatMap(DragModifier.init(rawValue:)) ?? .controlCommand }
        set { defaults.set(newValue.rawValue, forKey: "modifier") }
    }

    var shadow: Bool {
        get { defaults.object(forKey: "shadow") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "shadow") }
    }

    var preset: WobblePreset {
        get { defaults.string(forKey: "wobblyPreset").flatMap(WobblePreset.init(rawValue:)) ?? .realistic }
        set {
            defaults.set(newValue.rawValue, forKey: "wobblyPreset")
            if let values = newValue.settings { physics = values }
        }
    }

    var physics: WobblySettings {
        get {
            let fallback = WobblySettings.realistic
            return WobblySettings(
                friction: float("friction") ?? fallback.friction,
                spring: float("spring") ?? fallback.spring,
                speedup: float("speedup") ?? fallback.speedup,
                mass: float("mass") ?? fallback.mass)
        }
        set {
            defaults.set(Double(newValue.friction), forKey: "friction")
            defaults.set(Double(newValue.spring), forKey: "spring")
            defaults.set(Double(newValue.speedup), forKey: "speedup")
            defaults.set(Double(newValue.mass), forKey: "mass")
        }
    }

    var tilesX: Int {
        get { defaults.object(forKey: "tilesX") as? Int ?? Self.defaultTilesX }
        set { defaults.set(newValue, forKey: "tilesX") }
    }

    var tilesY: Int {
        get { defaults.object(forKey: "tilesY") as? Int ?? Self.defaultTilesY }
        set { defaults.set(newValue, forKey: "tilesY") }
    }

    var maximizeEffect: Bool {
        get { defaults.object(forKey: "maximizeEffect") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "maximizeEffect") }
    }

    var resizeEffect: Bool {
        get { defaults.object(forKey: "resizeEffect") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "resizeEffect") }
    }

    func resetToDefaults() {
        preset = .realistic
        tilesX = Self.defaultTilesX
        tilesY = Self.defaultTilesY
        maximizeEffect = true
        resizeEffect = false
    }

    private func float(_ key: String) -> Float? {
        (defaults.object(forKey: key) as? Double).map(Float.init)
    }
}
