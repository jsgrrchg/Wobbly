# Wobbly

Compiz-style wobbly windows for macOS. Drag a window and it wobbles like jelly, then settles where you drop it. Optional effects also play when a window is maximized or resized, and closing a window can burn, shatter, melt or dissolve it with one of 30 GPU shader effects.

Wobbly is a menu bar app with no private APIs and no dependencies.

https://github.com/user-attachments/assets/40bc5530-d253-4d47-bc57-3eccdac83d70

## Installing

Requires macOS 14 or later, on Apple Silicon or Intel.

Download the DMG from Releases and drag Wobbly to `/Applications`. The app is not notarized, so the first time you open it macOS will block it: go to **System Settings → Privacy & Security** and click **Open Anyway**.

## Usage

- **Drag from the title bar** as usual, or
- **Hold the shortcut** (⌃⌘ by default) and drag a window from anywhere.

The menu bar icon lets you pick a preset (Subtle, Realistic, Exaggerated, Extreme), fine-tune friction, spring, speedup, mass and mesh density, and toggle the shadow and the maximize and resize effects.

### Close effects

When a window closes, it is replaced by an animation drawn on the GPU. Pick the effect in the menu bar under **Close Effect**: one of the 30 effects below, **Random** (a different one every time) or **Off**. The **Duration** slider scales the animation time of every effect (0.25× to 3×). Fire is the default.

Aperture Panels, Apparition, Aura Glow, Broken Glass, Doom, Energize A, Energize B, Fire, Focus, Glide, Glitch, Hexagon, Incinerate, Materialize, Matrix, Morph, Mushroom, Paint Brush, Pixelate, Pixel Wheel, Pixel Wipe, Portal, RGB Warp, Snap of Disintegration, Team Rocket, T-Rex Attack, TV Effect, TV Glitch, Wisps and Wormhole.

The effect plays when you close a window with:

- the close button (the red one), or
- **⌘W** (and **⌘Q**, for the focused window).

Minimizing, hiding, switching Spaces, closing a tab with ⌘W, or a close that the app refuses (an unsaved-changes sheet) don't play it. Effects that start at the pointer (Incinerate, Pixel Wipe) use the position of the mouse when the window closes. The effects that need the desktop behind the window (Aperture Panels, Morph, Wormhole) only animate the window: the real desktop shows through instead of being warped.

## Permissions

| Permission | Why |
|---|---|
| **Accessibility** | Watch mouse events and move windows. |
| **Screen Recording** | Capture the dragged or closing window so it can be drawn deformed or animated. Without it, windows move rigidly and close without an effect. |

## How it works

When a window is grabbed it is captured with ScreenCaptureKit, drawn on a deformed mesh by Metal in a transparent overlay, and the real window is moved off-screen through the Accessibility API. Once the animation settles, the real window is put back at its final position.

An app closes its windows by itself, so Wobbly can't intercept a close: it captures the window beforehand and watches it. A click near the top-left corner of a window captures it, and so does holding ⌘ (the capture is refreshed while ⌘ is held; keystrokes are never read). When macOS starts to fade the window out, or removes it, the capture is drawn by the effect's Metal shader in a transparent overlay, over the desktop that the closed window left. The shaders are in `Sources/WobblyEffects/Resources/Shaders`: each effect is one Metal file, ported from the GLSL of Burn-My-Windows.

## Building

Requires macOS 14 or later and Xcode 26 or later.

```sh
swift build                # build
swift test                 # run the physics and effect tests
scripts/build-app.sh       # package and sign build/Wobbly.app

# Render the close effects headlessly: checks every shader, texture and seed,
# and writes one contact sheet (PNG) per effect.
swift run wobbly-effects-preview --check --out /tmp/wobbly-effects
swift run wobbly-effects-preview --effect fire --out /tmp/wobbly-effects
```

`build-app.sh` signs with your "Apple Development" identity if you have one, or with `SIGN_IDENTITY` if set. Otherwise it falls back to ad-hoc signing, in which case macOS asks for permissions again after every build.

## Credits

- The wobbly model comes from the Compiz wobbly plugin by David Reveman (Novell), with the spring model by Kristian Høgsberg.
- The physics, presets and resize effect are ported from the GNOME Shell extension [Compiz windows effect](https://github.com/hermes83/compiz-windows-effect) by Mauro Pepe.
- The trick for hiding the real window comes from [AeroSpace](https://github.com/nikitabobko/AeroSpace).
- The close effects, their settings and their textures come from [Burn-My-Windows](https://github.com/Schneegans/Burn-My-Windows) by Simon Schneegans: the GLSL shaders were ported to Metal. The brush, claws, dust, matrix font and shard textures are licensed CC-BY-4.0.

## License

Wobbly is licensed under the [GNU General Public License v3.0 or later](LICENSE). The resize effect is ported from Compiz windows effect, and the close effects from Burn-My-Windows, which are GPL-3.0-or-later, so Wobbly is a derivative work under the same license. Third-party notices are in [NOTICE](NOTICE).
