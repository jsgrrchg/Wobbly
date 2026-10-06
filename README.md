# Wobbly

Compiz-style wobbly windows for macOS. Drag a window and it wobbles like jelly, then settles where you drop it. Optional effects also play when a window is maximized or resized.

Wobbly is a menu bar app with no private APIs and no dependencies.

https://github.com/user-attachments/assets/510ff9e4-de24-4584-a43f-265a82f9ff4b

## Installing

Requires macOS 14 or later, on Apple Silicon or Intel.

Download the DMG from Releases and drag Wobbly to `/Applications`. The app is not notarized, so the first time you open it macOS will block it: go to **System Settings → Privacy & Security** and click **Open Anyway**.

## Usage

- **Drag from the title bar** as usual, or
- **Hold the shortcut** (⌃⌘ by default) and drag a window from anywhere.

The menu bar icon lets you pick a preset (Subtle, Realistic, Exaggerated, Extreme), fine-tune friction, spring, speedup, mass and mesh density, and toggle the shadow and the maximize and resize effects.

## Permissions

| Permission | Why |
|---|---|
| **Accessibility** | Watch mouse events and move windows. |
| **Screen Recording** | Capture the dragged window so it can be drawn deformed. Without it, windows move rigidly. |

## How it works

When a window is grabbed it is captured with ScreenCaptureKit, drawn on a deformed mesh by Metal in a transparent overlay, and the real window is moved off-screen through the Accessibility API. Once the animation settles, the real window is put back at its final position.

## Building

Requires macOS 14 or later and Xcode 26 or later.

```sh
swift build                # build
swift test                 # run the physics tests
scripts/build-app.sh       # package and sign build/Wobbly.app
```

`build-app.sh` signs with your "Apple Development" identity if you have one, or with `SIGN_IDENTITY` if set. Otherwise it falls back to ad-hoc signing, in which case macOS asks for permissions again after every build.

## Credits

- The wobbly model comes from the Compiz wobbly plugin by David Reveman (Novell), with the spring model by Kristian Høgsberg.
- The physics, presets and resize effect are ported from the GNOME Shell extension [Compiz windows effect](https://github.com/hermes83/compiz-windows-effect) by Mauro Pepe.
- The trick for hiding the real window comes from [AeroSpace](https://github.com/nikitabobko/AeroSpace).

## License

Wobbly is licensed under the [GNU General Public License v3.0 or later](LICENSE). The resize effect is ported from Compiz windows effect, which is GPL-3.0-or-later, so Wobbly is a derivative work under the same license. Third-party notices are in [NOTICE](NOTICE).
