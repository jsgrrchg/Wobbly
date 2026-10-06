// swift-tools-version: 5.9
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "Wobbly",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "WobblyCore"),
        .executableTarget(name: "Wobbly", dependencies: ["WobblyCore"]),
        .testTarget(name: "WobblyCoreTests", dependencies: ["WobblyCore"]),
    ]
)
