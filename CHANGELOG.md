# Changelog

All notable changes to Wobbly are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1]

### Fixed

- **Windows vanishing when dragged on some Spaces.** The dragged window was matched to its Accessibility
  element by frame, but an app's window list also includes its windows on other Spaces. Two windows with
  the same frame (maximized or tiled, for example) could be confused, so the wrong one was hidden and the
  one being dragged seemed to disappear. Windows are now matched by their exact window ID.
- **Dragging a window switching to another Space.** Activating the window's app could make macOS jump to a
  Space holding another of its windows. The dragged window is now made the app's main window before the
  app is activated.
- **Shadow jumping on release.** The overlay drew an approximated shadow that was smaller and darker than
  the native one, so it visibly changed when the real window took over. The overlay now draws the
  window's own native shadow, captured along with it, so the handover is seamless.
- **Title bar and shadow changing on release for background windows.** A window grabbed from the
  background was captured with its inactive look. It is now captured again once it becomes active.
- **Shadow flicker when grabbing and releasing a window.** For a frame or two, both the native and the
  overlay shadows were drawn, or neither. The overlay now switches shadows in the same frame the real
  window is hidden or put back.

### Changed

- **Faster start of the effect.** The window no longer moves rigidly for a moment before it starts to
  wobble, especially when switching between windows, apps or Spaces:
  - The list of capturable windows is kept up to date in the background and covers every Space.
  - Screen capture is warmed up at launch, so the first drag is as fast as the rest.
  - A slow app no longer delays dragging windows of other apps.
  - Mouse clicks do less work before being passed on.

## [0.1.0]

- Initial release: Compiz-style wobbly windows for macOS, with maximize and resize effects.

[0.1.1]: https://github.com/jsgrrchg/Wobbly/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/jsgrrchg/Wobbly/releases/tag/v0.1.0
