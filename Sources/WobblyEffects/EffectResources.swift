// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Metal

public enum EffectError: Error, CustomStringConvertible {
    case resourceMissing(String)
    case compilation(String)
    case textureDecoding(String)

    public var description: String {
        switch self {
        case .resourceMissing(let name): return "missing resource \(name)"
        case .compilation(let message): return "shader compilation failed: \(message)"
        case .textureDecoding(let message): return "texture decoding failed: \(message)"
        }
    }
}

enum EffectResources {
    /// SwiftPM resource bundle. Inside an app it sits in `Contents/Resources`, where `Bundle.module` doesn't look.
    static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Wobbly_WobblyEffects.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()

    static func url(_ name: String, extension ext: String, directory: String) throws -> URL {
        guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources/\(directory)") else {
            throw EffectError.resourceMissing("\(directory)/\(name).\(ext)")
        }
        return url
    }

    static func text(_ name: String) throws -> String {
        try String(contentsOf: url(name, extension: "metal", directory: "Shaders"), encoding: .utf8)
    }
}

/// Builds the Metal source of an effect: the shared helpers, the effect's own code, and a generated `FX` struct
/// that holds the standard uniforms of Burn-My-Windows plus one macro per effect parameter.
///
/// An effect file has two parts separated by a `//@@` line: declarations that don't depend on uniforms
/// (constants, pure functions) come first, and the members of `FX` (helpers that read uniforms, and `run()`) after.
enum EffectShaderSource {
    private static let marker = "//@@"

    static func source(for effect: CloseEffect) throws -> String {
        let file = try EffectResources.text(effect.shaderName)
        let parts = file.components(separatedBy: marker + "\n")
        guard parts.count == 2 else {
            throw EffectError.compilation("\(effect.shaderName).metal must contain exactly one '\(marker)' line")
        }

        var context = EffectContext(windowSize: SIMD2(800, 600), seed: 0)
        let macros = effect.parameters(&context).enumerated()
            .map { "  #define \($1.name) \($1.accessor(slot: $0))" }
            .joined(separator: "\n")

        return try [
            EffectResources.text("common"),
            parts[0],
            "struct FX {",
            EffectResources.text("members"),
            macros,
            parts[1],
            "};",
            EffectResources.text("footer"),
        ].joined(separator: "\n")
    }
}
