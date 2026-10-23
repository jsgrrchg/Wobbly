// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Metal
import WobblyEffects

// Renders the close effects on the GPU without opening any window.
//
//   swift run wobbly-effects-preview [--out DIR] [--effect ID] [--check]
//
// Writes one contact sheet (PNG) per effect into DIR (default: a temporary folder). With --check it also verifies
// that every effect starts with the window visible and ends with it gone, and exits with status 1 otherwise.

var arguments = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

let output = URL(fileURLWithPath: option("--out") ?? NSTemporaryDirectory() + "wobbly-effects")
let check = arguments.contains("--check")
let effects: [CloseEffect]
if let id = option("--effect") {
    guard let effect = CloseEffect(rawValue: id) else {
        FileHandle.standardError.write(Data("Unknown effect '\(id)'. Available: \(CloseEffect.allCases.map(\.rawValue).joined(separator: ", "))\n".utf8))
        exit(2)
    }
    effects = [effect]
} else {
    effects = CloseEffect.allCases
}

do {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let preview = try EffectPreview()
    var failed = false
    for effect in effects {
        do {
            try preview.renderer.prepare(effect)
            var line = effect.title.padding(toLength: 24, withPad: " ", startingAt: 0)
            if check {
                let scene = preview.scene(for: effect)
                let interior = EffectPreview.interior(of: scene)
                let start = try preview.render(scene, progress: 0).meanAlpha(in: interior)
                let middle = try preview.render(scene, progress: 0.6).meanAlpha(in: interior)
                let late = try preview.render(scene, progress: 0.95).meanAlpha(in: interior)
                let end = try preview.render(scene, progress: 1).meanAlpha(in: interior)
                let ok = start > 0.85 && (end < 0.2 || !effect.vanishesCompletely)
                    && (late <= middle + 0.05 || !effect.vanishesCompletely)
                failed = failed || !ok
                line += String(format: "start %.2f  mid %.2f  late %.2f  end %.2f  %@", start, middle, late, end, ok ? "ok" : "FAIL")
            }
            if let sheet = try preview.contactSheet(for: effect) {
                try EffectPreview.writePNG(sheet, to: output.appendingPathComponent("\(effect.rawValue).png"))
            }
            print(line)
        } catch {
            failed = true
            print("\(effect.title): \(error)")
        }
    }
    print("Contact sheets in \(output.path)")

    if check {
        // Textures must be read exactly as stored (reference values from an independent decoder, Pillow).
        let references: [(EffectTexture, Int, Int, [UInt8])] = [
            (.brush, 512, 512, [76, 63, 106, 72]), (.brush, 300, 700, [112, 100, 116, 166]),
            (.matrixFont, 40, 40, [188, 188, 188, 255]), (.claws, 400, 400, [22, 22, 22, 255]),
            (.shards, 256, 256, [133, 41, 0, 255]), (.dust, 100, 100, [84, 209, 0, 255]),
        ]
        for (kind, x, y, expected) in references {
            let texture = try EffectTextureLoader.load(kind, device: preview.device)
            var pixel = [UInt8](repeating: 0, count: 4)
            texture.getBytes(&pixel, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
            let ok = pixel == expected
            failed = failed || !ok
            print("texture \(kind.rawValue) (\(x), \(y)): \(pixel) \(ok ? "ok" : "FAIL, expected \(expected)")")
        }

        // The same seed must give the same frame, and another seed another one.
        for effect in [CloseEffect.incinerate, .brokenGlass, .snapOfDisintegration] {
            let a = try preview.render(preview.scene(for: effect, seed: 5), progress: 0.5).pixels
            let b = try preview.render(preview.scene(for: effect, seed: 5), progress: 0.5).pixels
            let c = try preview.render(preview.scene(for: effect, seed: 6), progress: 0.5).pixels
            let ok = a == b && a != c
            failed = failed || !ok
            print("seed \(effect.title): \(ok ? "ok" : "FAIL")")
        }
    }
    exit(failed ? 1 : 0)
} catch {
    print("error: \(error)")
    exit(1)
}
