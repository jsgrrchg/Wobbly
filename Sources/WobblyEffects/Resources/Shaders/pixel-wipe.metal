// Pixel Wipe: pixelates the window and hides the pixels radially, starting from the pointer.
// Ported from Burn-My-Windows (resources/shaders/pixel-wipe.frag).
// SPDX-FileCopyrightText: Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

constant float FADE_WIDTH = 1.0;  // Width of the transition.
//@@
  float4 run() {
    // A 2D gradient in [0..1] which covers the entire window: dark regions are hidden first.
    // The center of the radial gradient is positioned at uStartPos.
    float circle = length(iTexCoord - uStartPos);

    float progress = easeOutQuad(uProgress);
    progress       = ((1.0 - progress) * (1.0 + FADE_WIDTH) - 1.0 + circle) / FADE_WIDTH;
    progress       = smoothstep(0.0, 1.0, progress);
    progress       = uForOpening ? progress : 1.0 - progress;

    // The current level of pixelation increases with the progress.
    float pixelSize = ceil(uPixelSize * progress + 1.0);
    vec2 pixelGrid  = vec2(pixelSize) / uSize;
    vec2 texcoord   = iTexCoord - mod(iTexCoord, pixelGrid) + pixelGrid * 0.5;
    vec4 oColor     = getInputColor(texcoord);

    // Hide pixels in the transition zone.
    float random = simplex2DFractal(texcoord * uSize / 20.0) * 1.5 - 0.25;
    if (progress > random) {
      oColor.a *= max(0.0, 1.0 - (progress - random) * 10.0);
    }
    return oColor;
  }
