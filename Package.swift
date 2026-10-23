// swift-tools-version: 5.9
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "Wobbly",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "WobblyCore"),
        // Window-close effects: Metal shaders ported from Burn-My-Windows.
        .target(name: "WobblyEffects", resources: [.copy("Resources")]),
        // Renders the effects headlessly: `swift run wobbly-effects-preview --check`.
        .executableTarget(name: "wobbly-effects-preview", dependencies: ["WobblyEffects"], path: "Sources/WobblyEffectsPreview"),
        .executableTarget(name: "Wobbly", dependencies: ["WobblyCore", "WobblyEffects"]),
        .testTarget(name: "WobblyCoreTests", dependencies: ["WobblyCore"]),
        .testTarget(name: "WobblyEffectsTests", dependencies: ["WobblyEffects"]),
    ]
)
